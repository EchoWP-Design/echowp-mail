import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pg/dart_pg.dart' as pg;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'storage.dart';

/// Kurzinfo zu einem OpenPGP-Schlüssel (für Anzeige und Prüfungen).
class PgpKeyInfo {
  final String fingerprint; // Hex, Großbuchstaben
  final List<String> userIds;
  final DateTime created;
  final DateTime? expires;
  final bool hasSecret;
  const PgpKeyInfo(this.fingerprint, this.userIds, this.created, this.expires, {this.hasSecret = false});

  /// Fingerabdruck in Vierergruppen (wie in Thunderbird/GnuPG).
  String get groupedFingerprint {
    final b = StringBuffer();
    for (var i = 0; i < fingerprint.length; i += 4) {
      if (i > 0) b.write(i == fingerprint.length ~/ 2 ? '  ' : ' ');
      b.write(fingerprint.substring(i, i + 4 > fingerprint.length ? fingerprint.length : i + 4));
    }
    return b.toString();
  }

  /// E-Mail-Adressen aus den Benutzerkennungen („Name <mail>“).
  List<String> get emails => [
        for (final u in userIds)
          if (RegExp(r'<([^>]+)>').firstMatch(u) case final m?) m.group(1)!.toLowerCase() else if (u.contains('@')) u.trim().toLowerCase(),
      ];

  bool get expired => expires != null && expires!.isBefore(DateTime.now());
}

String _hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

PgpKeyInfo _info(pg.BaseKey k, {bool secret = false}) => PgpKeyInfo(
      _hex(k.fingerprint),
      [for (final u in k.users) u.userID],
      k.creationTime,
      k.expirationTime,
      hasSecret: secret,
    );

class PgpException implements Exception {
  final String message;
  const PgpException(this.message);
  @override
  String toString() => message;
}

/// OpenPGP (dart_pg, klassische v4-Schlüssel: Ed25519 + Curve25519 – wie GnuPG-Standard).
///
/// Der geheime Schlüssel liegt passwortgeschützt (OpenPGP-S2K) im sicheren Speicher
/// des Geräts, aufgeteilt in Stücke (Windows-Anmeldeinformationen fassen nur ~2,5 KB).
/// Er wird nicht über Google Drive abgeglichen. Das Passwort wird nie gespeichert,
/// höchstens bis zum Beenden der App im Arbeitsspeicher gehalten.
class PgpService {
  PgpService({FlutterSecureStorage? storage}) : _sec = storage ?? Storage.secure;
  final FlutterSecureStorage _sec;

  /// Stückgröße im sicheren Speicher (für Tests änderbar).
  static int chunkSize = 1800;
  final Map<String, String> _armoredSecret = {}; // accountId → armored (gesperrt)
  final Map<String, pg.PrivateKey> _unlocked = {}; // accountId → entsperrt (nur Sitzung)

  // ---------------------------------------------------------------- Speicher

  Future<void> load(Iterable<String> accountIds) async {
    for (final id in accountIds) {
      final a = await _readSecret(id);
      if (a != null) _armoredSecret[id] = a;
    }
  }

  Future<String?> _readSecret(String id) async {
    try {
      final n = int.tryParse(await _sec.read(key: 'pgp_n_$id') ?? '');
      if (n == null || n <= 0) return null;
      final b = StringBuffer();
      for (var i = 0; i < n; i++) {
        final part = await _sec.read(key: 'pgp_${id}_$i');
        if (part == null) return null;
        b.write(part);
      }
      return b.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSecret(String id, String armored) async {
    await _deleteSecret(id);
    final parts = <String>[for (var i = 0; i < armored.length; i += chunkSize)
        armored.substring(i, i + chunkSize > armored.length ? armored.length : i + chunkSize)];
    for (var i = 0; i < parts.length; i++) {
      await _sec.write(key: 'pgp_${id}_$i', value: parts[i]);
    }
    await _sec.write(key: 'pgp_n_$id', value: '${parts.length}');
  }

  Future<void> _deleteSecret(String id) async {
    final n = int.tryParse(await _sec.read(key: 'pgp_n_$id') ?? '') ?? 0;
    for (var i = 0; i < n; i++) {
      await _sec.delete(key: 'pgp_${id}_$i');
    }
    await _sec.delete(key: 'pgp_n_$id');
  }

  // ---------------------------------------------------------------- eigene Schlüssel

  bool hasKey(String accountId) => _armoredSecret.containsKey(accountId);
  bool isUnlocked(String accountId) => _unlocked.containsKey(accountId);

  PgpKeyInfo? ownKey(String accountId) {
    final a = _armoredSecret[accountId];
    if (a == null) return null;
    try {
      return _info(pg.OpenPGP.readPrivateKey(a) as pg.BaseKey, secret: true);
    } catch (_) {
      return null;
    }
  }

  /// Öffentlicher Teil des eigenen Schlüssels (zum Weitergeben).
  String? ownPublicArmored(String accountId) {
    final a = _armoredSecret[accountId];
    if (a == null) return null;
    return pg.OpenPGP.readPrivateKey(a).publicKey.armor();
  }

  String? ownSecretArmored(String accountId) => _armoredSecret[accountId];

  /// Neues Schlüsselpaar (Ed25519 zum Signieren, Curve25519 zum Verschlüsseln).
  Future<PgpKeyInfo> generate(String accountId, String name, String email, String passphrase) async {
    if (passphrase.length < 8) throw const PgpException('Das Passwort muss mindestens 8 Zeichen haben.');
    final uid = name.trim().isEmpty ? email : '${name.trim()} <$email>';
    final key = pg.OpenPGP.generateKey([uid], passphrase, type: pg.KeyType.ecc, curve: pg.Ecc.ed25519) as pg.PrivateKey;
    await _writeSecret(accountId, key.armor());
    _armoredSecret[accountId] = key.armor();
    _unlocked.remove(accountId);
    return _info(key, secret: true);
  }

  /// Geheimen Schlüssel importieren (z. B. aus Thunderbird, GnuPG oder Mailvelope exportiert).
  Future<PgpKeyInfo> importSecret(String accountId, String armored, String passphrase) async {
    final pg.PrivateKey key;
    try {
      key = pg.OpenPGP.readPrivateKey(armored.trim()) as pg.PrivateKey;
    } catch (_) {
      throw const PgpException('Kein gültiger geheimer OpenPGP-Schlüssel (Datei beginnt mit '
          '„-----BEGIN PGP PRIVATE KEY BLOCK-----“).');
    }
    try {
      key.decrypt(passphrase);
    } catch (_) {
      throw const PgpException('Passwort falsch – der Schlüssel ließ sich nicht entsperren.');
    }
    final a = key.armor();
    await _writeSecret(accountId, a);
    _armoredSecret[accountId] = a;
    _unlocked.remove(accountId);
    return _info(key, secret: true);
  }

  Future<void> removeKey(String accountId) async {
    await _deleteSecret(accountId);
    _armoredSecret.remove(accountId);
    _unlocked.remove(accountId);
  }

  /// Entsperrt den geheimen Schlüssel für diese Sitzung. Wirft bei falschem Passwort.
  void unlock(String accountId, String passphrase) {
    final a = _armoredSecret[accountId];
    if (a == null) throw const PgpException('Für dieses Konto ist kein eigener Schlüssel eingerichtet.');
    try {
      _unlocked[accountId] = pg.OpenPGP.decryptPrivateKey(a, passphrase) as pg.PrivateKey;
    } catch (_) {
      throw const PgpException('Passwort falsch.');
    }
  }

  void lockAll() => _unlocked.clear();

  // ---------------------------------------------------------------- öffentliche Schlüssel

  /// Prüft einen öffentlichen Schlüssel (Kontakt) und liefert die Kurzinfo.
  static PgpKeyInfo readPublicInfo(String armored) {
    try {
      final t = armored.trim();
      final k = t.contains('PRIVATE KEY BLOCK') ? pg.OpenPGP.readPrivateKey(t).publicKey : pg.OpenPGP.readPublicKey(t);
      return _info(k as pg.BaseKey);
    } catch (_) {
      throw const PgpException('Kein gültiger öffentlicher OpenPGP-Schlüssel (Datei beginnt mit '
          '„-----BEGIN PGP PUBLIC KEY BLOCK-----“).');
    }
  }

  /// Nur den öffentlichen Teil behalten (falls versehentlich ein geheimer Schlüssel kommt).
  static String publicOnly(String armored) {
    final t = armored.trim();
    return t.contains('PRIVATE KEY BLOCK')
        ? pg.OpenPGP.readPrivateKey(t).publicKey.armor()
        : pg.OpenPGP.readPublicKey(t).armor();
  }

  // ---------------------------------------------------------------- PGP/MIME (RFC 3156)

  /// Baut aus einer fertig gerenderten Mail (ohne Bcc) eine verschlüsselte und/oder signierte Mail.
  /// [recipientKeys]: öffentliche Schlüssel aller Empfänger (bei Verschlüsselung Pflicht).
  /// Rückgabe: vollständiger Mailtext (CRLF), bereit zum Versand.
  String protect({
    required String renderedMessage,
    required String accountId,
    required bool encrypt,
    required bool sign,
    List<String> recipientKeys = const [],
  }) {
    if (!encrypt && !sign) return renderedMessage;
    final signer = sign ? _unlocked[accountId] : null;
    if (sign && signer == null) throw const PgpException('Schlüssel ist gesperrt – bitte Passwort eingeben.');
    final (outer, entity) = splitForPgp(renderedMessage);
    final boundary = 'echowp-pgp-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

    if (!encrypt) {
      // multipart/signed: Signatur über exakt die Bytes des ersten Teils (CRLF)
      final sigObj = pg.OpenPGP.signDetached(
        pg.OpenPGP.createLiteralMessage(Uint8List.fromList(utf8.encode(entity))),
        [signer!],
      );
      final sig = sigObj.armor();
      final micalg = 'pgp-${sigObj.hashAlgorithms.isEmpty ? 'sha256' : sigObj.hashAlgorithms.first.name}';
      return '$outer'
          'Content-Type: multipart/signed; micalg=$micalg;\r\n'
          ' protocol="application/pgp-signature"; boundary="$boundary"\r\n'
          '\r\n'
          'This is an OpenPGP/MIME signed message (RFC 4880 and 3156)\r\n'
          '--$boundary\r\n'
          '$entity\r\n'
          '--$boundary\r\n'
          'Content-Type: application/pgp-signature; name="OpenPGP_signature.asc"\r\n'
          'Content-Description: OpenPGP digital signature\r\n'
          'Content-Disposition: attachment; filename="OpenPGP_signature.asc"\r\n'
          '\r\n'
          '${_crlf(sig)}\r\n'
          '--$boundary--\r\n';
    }

    // Verschlüsseln (an alle Empfänger und an sich selbst, damit die gesendete Kopie lesbar bleibt)
    final own = _armoredSecret[accountId];
    final keys = [
      for (final k in recipientKeys) pg.OpenPGP.readPublicKey(k.trim()),
      if (own != null) pg.OpenPGP.readPrivateKey(own).publicKey,
    ];
    if (keys.isEmpty) throw const PgpException('Keine Schlüssel zum Verschlüsseln.');
    // Innen: geschützte Kopfzeilen (From/To/Cc/Subject/Date) + Inhalt, wie Thunderbird
    final inner = '${_protectedHeaders(outer)}$entity';
    final enc = pg.OpenPGP.encrypt(
      pg.OpenPGP.createLiteralMessage(Uint8List.fromList(utf8.encode(inner))),
      encryptionKeys: keys,
      signingKeys: [if (signer != null) signer],
    ).armor();
    return '$outer'
        'Content-Type: multipart/encrypted;\r\n'
        ' protocol="application/pgp-encrypted"; boundary="$boundary"\r\n'
        '\r\n'
        'This is an OpenPGP/MIME encrypted message (RFC 4880 and 3156)\r\n'
        '--$boundary\r\n'
        'Content-Type: application/pgp-encrypted\r\n'
        'Content-Description: PGP/MIME version identification\r\n'
        '\r\n'
        'Version: 1\r\n'
        '\r\n'
        '--$boundary\r\n'
        'Content-Type: application/octet-stream; name="encrypted.asc"\r\n'
        'Content-Description: OpenPGP encrypted message\r\n'
        'Content-Disposition: inline; filename="encrypted.asc"\r\n'
        '\r\n'
        '${_crlf(enc)}\r\n'
        '--$boundary--\r\n';
  }

  static String _crlf(String s) => s.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n').trimRight();

  static String _protectedHeaders(String outer) {
    final keep = {'from', 'to', 'cc', 'subject', 'date', 'reply-to'};
    final b = StringBuffer();
    for (final f in _fields(outer)) {
      if (keep.contains(f.$1)) b.write(f.$2);
    }
    return b.toString();
  }

  /// Zerlegt eine gerenderte Mail in (äußere Kopfzeilen ohne Content-*, innerer MIME-Teil).
  /// Beide mit CRLF; die äußeren Kopfzeilen enden mit CRLF, der innere Teil ohne abschließendes CRLF.
  static (String, String) splitForPgp(String rendered) {
    final t = rendered.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
    final cut = t.indexOf('\r\n\r\n');
    if (cut < 0) throw const PgpException('Mail ohne Kopfzeilen.');
    final head = t.substring(0, cut + 2);
    var body = t.substring(cut + 4);
    while (body.endsWith('\r\n')) {
      body = body.substring(0, body.length - 2);
    }
    final outer = StringBuffer();
    final content = StringBuffer();
    for (final (name, raw) in _fields(head)) {
      if (name == 'bcc') continue; // nie mitsenden
      if (name.startsWith('content-')) {
        content.write(raw);
      } else if (name != 'mime-version') {
        outer.write(raw);
      }
    }
    outer.write('MIME-Version: 1.0\r\n');
    return (outer.toString(), '$content\r\n$body');
  }

  /// Kopfzeilen (mit Fortsetzungszeilen) als (kleingeschriebener Name, Rohtext inkl. CRLF).
  static List<(String, String)> _fields(String head) {
    final out = <(String, String)>[];
    String? name;
    final cur = StringBuffer();
    for (final line in head.split('\r\n')) {
      if (line.isEmpty) continue;
      if ((line.startsWith(' ') || line.startsWith('\t')) && name != null) {
        cur.write('$line\r\n');
        continue;
      }
      if (name != null) out.add((name, cur.toString()));
      cur.clear();
      final i = line.indexOf(':');
      name = i > 0 ? line.substring(0, i).trim().toLowerCase() : '';
      cur.write('$line\r\n');
    }
    if (name != null) out.add((name, cur.toString()));
    return out;
  }
}

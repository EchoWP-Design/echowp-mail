import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_pg/dart_pg.dart' as pg;
import 'package:enough_mail/enough_mail.dart' as em;
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

/// Art einer empfangenen OpenPGP-Mail.
enum PgpKind { none, encrypted, signed }

/// Ergebnis der Signaturprüfung.
enum PgpSig { none, valid, invalid, unknownKey }

/// OpenPGP-Zustand einer geöffneten Mail (für die Statusleiste).
class PgpStatus {
  final PgpKind kind;
  final bool decrypted;
  final PgpSig sig;
  final String? signer; // Benutzerkennung des Signaturschlüssels
  final String? error;
  const PgpStatus(this.kind, {this.decrypted = false, this.sig = PgpSig.none, this.signer, this.error});
  static const plain = PgpStatus(PgpKind.none);

  bool get isEncrypted => kind == PgpKind.encrypted;

  /// Inhalt darf nicht an KI/Benachrichtigungen gehen (verschlüsselt empfangen).
  bool get confidential => kind == PgpKind.encrypted;

  PgpStatus copyWith({bool? decrypted, PgpSig? sig, String? signer, String? error}) =>
      PgpStatus(kind, decrypted: decrypted ?? this.decrypted, sig: sig ?? this.sig, signer: signer ?? this.signer, error: error);
}

/// Entschlüsselter bzw. geprüfter Inhalt.
class PgpOpened {
  /// Innere MIME-Nachricht (PGP/MIME), sonst null.
  final em.MimeMessage? mime;

  /// Reiner Text (Inline-PGP), sonst null.
  final String? text;
  final PgpSig sig;
  final String? signer;
  const PgpOpened({this.mime, this.text, this.sig = PgpSig.none, this.signer});
}

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
    // dart_pg 2.0.0 scheitert, wenn der zufällige Ed25519-Schlüssel mit 0x00 beginnt (~1/256):
    // dann einfach neu würfeln.
    pg.PrivateKey? key;
    for (var i = 0; key == null; i++) {
      try {
        key = pg.OpenPGP.generateKey([uid], passphrase, type: pg.KeyType.ecc, curve: pg.Ecc.ed25519) as pg.PrivateKey;
      } catch (_) {
        if (i >= 7) rethrow;
      }
    }
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

  // ---------------------------------------------------------------- Empfangen

  static const _msgStart = '-----BEGIN PGP MESSAGE-----';
  static const _msgEnd = '-----END PGP MESSAGE-----';
  static const _signedStart = '-----BEGIN PGP SIGNED MESSAGE-----';
  static const _sigEnd = '-----END PGP SIGNATURE-----';

  /// Erkennt PGP/MIME (RFC 3156) und Inline-PGP. [text]: dekodierter Textteil der Mail.
  static PgpKind detect(em.MimeMessage m, String text) {
    final ct = m.getHeaderContentType();
    final type = ct?.mediaType.text.toLowerCase();
    final proto = (ct?.parameters['protocol'] ?? '').toLowerCase().replaceAll('"', '');
    if (type == 'multipart/encrypted' && proto == 'application/pgp-encrypted') return PgpKind.encrypted;
    if (type == 'multipart/signed' && proto == 'application/pgp-signature') return PgpKind.signed;
    if (text.contains(_msgStart) && text.contains(_msgEnd)) return PgpKind.encrypted;
    if (text.contains(_signedStart) && text.contains(_sigEnd)) return PgpKind.signed;
    return PgpKind.none;
  }

  static String? _block(String s, String start, String end) {
    final a = s.indexOf(start);
    if (a < 0) return null;
    final b = s.indexOf(end, a);
    if (b < 0) return null;
    return s.substring(a, b + end.length);
  }

  /// Öffentliche Schlüssel lesen; Unlesbares wird übersprungen.
  static List<pg.BaseKey> _keys(Iterable<String> armored) {
    final out = <pg.BaseKey>[];
    for (final a in armored) {
      try {
        out.add(pg.OpenPGP.readPublicKey(a.trim()) as pg.BaseKey);
      } catch (_) {}
    }
    return out;
  }

  /// Signaturprüfung zusammenfassen. [verify] liefert je passender Signatur (gültig?, Benutzerkennung).
  static (PgpSig, String?) _verdict(
      bool hasSignature, List<pg.BaseKey> keys, Iterable<(bool, String?)> Function(List<pg.BaseKey>) verify) {
    if (!hasSignature) return (PgpSig.none, null);
    if (keys.isEmpty) return (PgpSig.unknownKey, null);
    final List<(bool, String?)> v;
    try {
      v = verify(keys).toList();
    } catch (_) {
      return (PgpSig.invalid, null);
    }
    if (v.isEmpty) return (PgpSig.unknownKey, null);
    final ok = v.where((x) => x.$1).firstOrNull;
    if (ok != null) return (PgpSig.valid, ok.$2);
    return (PgpSig.invalid, v.first.$2);
  }

  /// Entschlüsselt eine empfangene Mail mit dem (entsperrten) Schlüssel des Kontos.
  /// [m]: vollständige Mail, [text]: dekodierter Textteil (für Inline-PGP),
  /// [senderKeys]: bekannte öffentliche Schlüssel des Absenders (für die Signatur).
  PgpOpened decryptMail(String accountId, em.MimeMessage m, String text, Iterable<String> senderKeys) {
    final key = _unlocked[accountId];
    if (key == null) {
      throw PgpException(hasKey(accountId)
          ? 'Schlüssel ist gesperrt – bitte Passwort eingeben.'
          : 'Für dieses Konto ist kein eigener OpenPGP-Schlüssel eingerichtet.');
    }
    final ct = m.getHeaderContentType();
    final isMime = ct?.mediaType.text.toLowerCase() == 'multipart/encrypted';
    String? armored;
    if (isMime) {
      for (final p in m.parts ?? const <em.MimePart>[]) {
        try {
          final t = p.decodeContentText() ?? '';
          armored = _block(t, _msgStart, _msgEnd);
          if (armored != null) break;
        } catch (_) {}
      }
      armored ??= _block(m.renderMessage(), _msgStart, _msgEnd);
    } else {
      armored = _block(text, _msgStart, _msgEnd);
    }
    if (armored == null) throw const PgpException('Kein verschlüsselter OpenPGP-Inhalt gefunden.');
    final pg.LiteralMessage lit;
    try {
      lit = pg.OpenPGP.decrypt(normalizeArmor(armored), decryptionKeys: [key]) as pg.LiteralMessage;
    } catch (_) {
      throw const PgpException('Entschlüsseln fehlgeschlagen – die Mail ist nicht für deinen Schlüssel '
          'verschlüsselt oder beschädigt.');
    }
    final keys = _keys(senderKeys);
    final (sig, signer) = _verdict(lit.signature.packets.isNotEmpty, keys, (k) => lit.verify(k).map((v) => (v.isVerified, v.userIDs.firstOrNull)));
    final plain = utf8.decode(lit.literalData.binary, allowMalformed: true);
    if (isMime) {
      return PgpOpened(mime: em.MimeMessage.parseFromText(plain.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n')),
          sig: sig, signer: signer);
    }
    // Inline: verschlüsselten Block im Text ersetzen
    return PgpOpened(text: text.replaceFirst(armored, plain.replaceAll('\r\n', '\n').trim()), sig: sig, signer: signer);
  }

  /// Prüft eine signierte Mail: multipart/signed (Signatur über die Bytes des ersten Teils)
  /// oder Inline-Klartextsignatur. Braucht keinen eigenen Schlüssel.
  static PgpOpened verifyMail(em.MimeMessage m, String text, Iterable<String> senderKeys) {
    final keys = _keys(senderKeys);
    final ct = m.getHeaderContentType();
    if (ct?.mediaType.text.toLowerCase() == 'multipart/signed') {
      final boundary = ct?.boundary;
      var raw = m.renderMessage();
      if (!raw.contains('\r\n')) raw = raw.replaceAll('\n', '\r\n');
      final bodyAt = raw.indexOf('\r\n\r\n');
      if (boundary == null || bodyAt < 0) return const PgpOpened(sig: PgpSig.invalid);
      final open = '--$boundary\r\n';
      final s0 = raw.indexOf(open, bodyAt);
      if (s0 < 0) return const PgpOpened(sig: PgpSig.invalid);
      final start = s0 + open.length;
      final end = raw.indexOf('\r\n--$boundary', start);
      if (end < 0) return const PgpOpened(sig: PgpSig.invalid);
      final entity = raw.substring(start, end);
      final sigArmor = _block(raw.substring(end), '-----BEGIN PGP SIGNATURE-----', _sigEnd);
      if (sigArmor == null) return const PgpOpened(sig: PgpSig.invalid);
      final pg.Signature signature;
      try {
        signature = pg.OpenPGP.readSignature(normalizeArmor(sigArmor)) as pg.Signature;
      } catch (_) {
        return const PgpOpened(sig: PgpSig.invalid);
      }
      // Bytes wie übertragen: Text aus IMAP kann als UTF-16 oder als Latin-1-Zeichen vorliegen
      final candidates = <Uint8List>[Uint8List.fromList(utf8.encode(entity))];
      if (entity.codeUnits.every((c) => c < 256) && entity.codeUnits.any((c) => c > 127)) {
        candidates.add(Uint8List.fromList(latin1.encode(entity)));
      }
      (PgpSig, String?) result = (PgpSig.invalid, null);
      for (final bytes in candidates) {
        result = _verdict(true, keys,
            (k) => pg.OpenPGP.createLiteralMessage(bytes)
                .verifyDetached(k, signature)
                .map((v) => (v.isVerified, v.userIDs.firstOrNull)));
        if (result.$1 != PgpSig.invalid) break;
      }
      return PgpOpened(sig: result.$1, signer: result.$2);
    }
    // Inline-Klartextsignatur
    final block = _block(text, _signedStart, _sigEnd);
    if (block == null) return const PgpOpened(sig: PgpSig.none);
    try {
      final armored = normalizeArmor(block);
      final msg = pg.OpenPGP.readSignedMessage(armored) as pg.SignedMessage;
      final (sig, signer) =
          _verdict(true, keys, (k) => msg.verify(k).map((v) => (v.isVerified, v.userIDs.firstOrNull)));
      return PgpOpened(text: text.replaceFirst(block, msg.text.replaceAll('\r\n', '\n').trim()), sig: sig, signer: signer);
    } catch (_) {
      return const PgpOpened(sig: PgpSig.invalid);
    }
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

  /// Armor aus einer Mail lesbar machen (dart_pg erwartet LF-Zeilenenden).
  static String normalizeArmor(String s) => s.replaceAll('\r\n', '\n').trim();

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

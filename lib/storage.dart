import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Abgeleiteter Schlüssel samt Salt/Iterationen (für wiederholte Verschlüsselung ohne Neuberechnung).
class DerivedKey {
  final List<int> keyBytes;
  final List<int> salt;
  final int iterations;
  const DerivedKey(this.keyBytes, this.salt, this.iterations);

  Map<String, dynamic> toJson() =>
      {'k': base64Encode(keyBytes), 's': base64Encode(salt), 'i': iterations};
  factory DerivedKey.fromJson(Map<String, dynamic> j) => DerivedKey(
      base64Decode(j['k'] as String), base64Decode(j['s'] as String), (j['i'] as num).toInt());
}

/// Konten (inkl. Passwörter), API-Key und Sync-Daten liegen im sicheren Speicher des Systems
/// (Android Keystore bzw. Windows DPAPI), sonstige Einstellungen in SharedPreferences.
class Storage {
  static const _magic1 = 'EWPM1';
  static const _magic2 = 'EWPM2';
  static const defaultIterations = 310000;

  static const secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _sec = secure;

  // Kontodaten ohne Passwort in SharedPreferences, das Passwort einzeln im sicheren Speicher
  // (hält jeden Eintrag klein – Windows-Anmeldeinformationen sind auf 2,5 KB begrenzt).
  Future<List<EchoAccount>> loadAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final ids = prefs.getStringList('account_ids') ?? [];
    final out = <EchoAccount>[];
    var migrated = false;
    for (final id in ids) {
      try {
        final raw = prefs.getString('acc_json_$id');
        if (raw != null) {
          final a = EchoAccount.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          a.password = await _sec.read(key: 'pw_$id') ?? '';
          out.add(a);
          continue;
        }
        // Altes Format (Version 1.0): komplettes Konto im sicheren Speicher
        final legacy = await _sec.read(key: 'acc_$id');
        if (legacy != null) {
          out.add(EchoAccount.fromJson(jsonDecode(legacy) as Map<String, dynamic>));
          migrated = true;
        }
      } catch (_) {}
    }
    if (migrated) {
      await saveAccounts(out);
      for (final id in ids) {
        try {
          await _sec.delete(key: 'acc_$id');
        } catch (_) {}
      }
    }
    return out;
  }

  Future<void> saveAccounts(List<EchoAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getStringList('account_ids') ?? [];
    for (final a in accounts) {
      final j = a.toJson()..remove('password');
      await prefs.setString('acc_json_${a.id}', jsonEncode(j));
      await _sec.write(key: 'pw_${a.id}', value: a.password);
    }
    for (final id in old) {
      if (!accounts.any((a) => a.id == id)) {
        await prefs.remove('acc_json_$id');
        await _sec.delete(key: 'pw_$id');
      }
    }
    await prefs.setStringList('account_ids', accounts.map((a) => a.id).toList());
  }

  Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    AppSettings s;
    try {
      final raw = prefs.getString('settings');
      s = raw == null ? AppSettings() : AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      s = AppSettings();
    }
    try {
      s.aiKey = await _sec.read(key: 'ai_key') ?? '';
    } catch (_) {}
    return s;
  }

  Future<void> saveSettings(AppSettings s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('settings', jsonEncode(s.toJson()));
    await _sec.write(key: 'ai_key', value: s.aiKey);
  }

  // ---------- Verschlüsselung (AES-256-GCM, Schlüssel per PBKDF2-HMAC-SHA256) ----------

  static final _aes = AesGcm.with256bits();

  static Future<DerivedKey> deriveKey(String password, {List<int>? salt, int iterations = defaultIterations}) async {
    final s = salt ?? List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
    final key = await kdf.deriveKeyFromPassword(password: password, nonce: s);
    return DerivedKey(await key.extractBytes(), s, iterations);
  }

  /// Format v2: "EWPM2" | Iterationen (4 Byte) | Salt (16) | Nonce+Chiffrat+MAC
  static Future<Uint8List> encryptWithKey(Map<String, dynamic> payload, DerivedKey k) async {
    final box = await _aes.encrypt(utf8.encode(jsonEncode(payload)), secretKey: SecretKey(k.keyBytes));
    final iter = ByteData(4)..setUint32(0, k.iterations);
    return (BytesBuilder()
          ..add(utf8.encode(_magic2))
          ..add(iter.buffer.asUint8List())
          ..add(k.salt)
          ..add(box.concatenation()))
        .toBytes();
  }

  /// Liest Salt und Iterationen aus der Datei (ohne zu entschlüsseln).
  static (List<int>, int) header(Uint8List data) {
    final magic = data.length >= 5 ? utf8.decode(data.sublist(0, 5), allowMalformed: true) : '';
    if (magic == _magic2 && data.length > 5 + 4 + 16 + 28) {
      final iter = ByteData.sublistView(data, 5, 9).getUint32(0);
      return (data.sublist(9, 25), iter);
    }
    if (magic == _magic1 && data.length > 5 + 16 + 28) {
      return (data.sublist(5, 21), 60000);
    }
    throw const FormatException('Keine gültige EchoWP-Mail-Datei.');
  }

  static Future<Map<String, dynamic>> decryptWithKey(Uint8List data, DerivedKey k) async {
    final magic = utf8.decode(data.sublist(0, 5), allowMalformed: true);
    final body = magic == _magic2 ? data.sublist(25) : data.sublist(21);
    final box = SecretBox.fromConcatenation(body,
        nonceLength: _aes.nonceLength, macLength: _aes.macAlgorithm.macLength);
    try {
      final clear = await _aes.decrypt(box, secretKey: SecretKey(k.keyBytes));
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } on SecretBoxAuthenticationError {
      throw const FormatException('Falsches Passwort oder beschädigte Datei.');
    }
  }

  Future<Uint8List> encrypt(Map<String, dynamic> payload, String password) async =>
      encryptWithKey(payload, await deriveKey(password));

  Future<Map<String, dynamic>> decrypt(Uint8List data, String password) async {
    final (salt, iter) = header(data);
    return decryptWithKey(data, await deriveKey(password, salt: salt, iterations: iter));
  }
}

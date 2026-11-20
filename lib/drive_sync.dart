import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'storage.dart';

class DriveException implements Exception {
  final String message;
  DriveException(this.message);
  @override
  String toString() => message;
}

class DeviceCode {
  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int interval;
  final DateTime expires;
  DeviceCode(this.deviceCode, this.userCode, this.verificationUrl, this.interval, this.expires);
}

/// Gerätebezogene Drive-Konfiguration (liegt nur im sicheren Speicher, wird nie synchronisiert).
class DriveConfig {
  String clientId;
  String clientSecret;
  String? refreshToken;
  DerivedKey? key;
  String? fileId;
  String? lastRemoteModified;
  DateTime? lastSync;

  DriveConfig({required this.clientId, required this.clientSecret});

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        'clientSecret': clientSecret,
        'refreshToken': refreshToken,
        'key': key?.toJson(),
        'fileId': fileId,
        'lastRemoteModified': lastRemoteModified,
        'lastSync': lastSync?.toIso8601String(),
      };

  factory DriveConfig.fromJson(Map<String, dynamic> j) =>
      DriveConfig(clientId: j['clientId'] as String? ?? '', clientSecret: j['clientSecret'] as String? ?? '')
        ..refreshToken = j['refreshToken'] as String?
        ..key = j['key'] == null ? null : DerivedKey.fromJson(Map<String, dynamic>.from(j['key'] as Map))
        ..fileId = j['fileId'] as String?
        ..lastRemoteModified = j['lastRemoteModified'] as String?
        ..lastSync = DateTime.tryParse(j['lastSync'] as String? ?? '');
}

/// Abgleich über Google Drive mit Scope drive.file: die App sieht ausschließlich
/// Dateien und Ordner, die sie selbst angelegt hat – nicht die übrigen Drive-Dateien.
class DriveSync {
  static const scope = 'https://www.googleapis.com/auth/drive.file';
  static const fileName = 'echowp-mail-sync.ewpm';
  static const folderName = 'EchoWP-Mail';
  static const _folderMime = 'application/vnd.google-apps.folder';
  static const _cfgKey = 'drive_cfg';

  DriveConfig? cfg;
  String? _accessToken;
  DateTime _accessExpires = DateTime(2000);

  bool get configured => cfg?.refreshToken != null && cfg?.key != null;

  Future<void> load() async {
    try {
      final raw = await Storage.secure.read(key: _cfgKey);
      cfg = raw == null ? null : DriveConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      cfg = null;
    }
  }

  Future<void> save() async {
    final c = cfg;
    if (c == null) {
      await Storage.secure.delete(key: _cfgKey);
    } else {
      await Storage.secure.write(key: _cfgKey, value: jsonEncode(c.toJson()));
    }
  }

  Future<void> disconnect() async {
    final token = cfg?.refreshToken;
    if (token != null) {
      try {
        await http.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': token});
      } catch (_) {}
    }
    cfg = null;
    _accessToken = null;
    await save();
  }

  Map<String, dynamic> _decode(http.Response r) {
    try {
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  // ---------------- OAuth 2.0 Device Flow ----------------

  Future<DeviceCode> startDeviceFlow(String clientId) async {
    final r = await http.post(Uri.parse('https://oauth2.googleapis.com/device/code'),
        body: {'client_id': clientId, 'scope': scope}).timeout(const Duration(seconds: 30));
    final j = _decode(r);
    if (r.statusCode != 200) {
      throw DriveException('Google lehnt die Anfrage ab: ${j['error_description'] ?? j['error'] ?? r.statusCode}. '
          'Client-ID und Client-Typ („Fernseher und Geräte mit begrenzter Eingabe“) prüfen.');
    }
    return DeviceCode(
      j['device_code'] as String,
      j['user_code'] as String,
      (j['verification_url'] ?? j['verification_uri'] ?? 'https://www.google.com/device') as String,
      (j['interval'] as num?)?.toInt() ?? 5,
      DateTime.now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 1800)),
    );
  }

  /// Wartet, bis der Nutzer den Code bestätigt hat. Gibt das Refresh-Token zurück.
  Future<String> waitForApproval(String clientId, String clientSecret, DeviceCode dc,
      {bool Function()? cancelled}) async {
    var interval = dc.interval;
    while (DateTime.now().isBefore(dc.expires)) {
      await Future.delayed(Duration(seconds: interval));
      if (cancelled?.call() ?? false) throw DriveException('Abgebrochen.');
      final r = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
        'client_id': clientId,
        'client_secret': clientSecret,
        'device_code': dc.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      }).timeout(const Duration(seconds: 30));
      final j = _decode(r);
      if (r.statusCode == 200) {
        _accessToken = j['access_token'] as String?;
        _accessExpires = DateTime.now().add(Duration(seconds: ((j['expires_in'] as num?)?.toInt() ?? 3600) - 60));
        final rt = j['refresh_token'] as String?;
        if (rt == null) throw DriveException('Google hat kein Refresh-Token geliefert.');
        return rt;
      }
      switch (j['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          interval += 5;
          continue;
        case 'access_denied':
          throw DriveException('Zugriff wurde abgelehnt.');
        case 'expired_token':
          throw DriveException('Der Code ist abgelaufen – bitte erneut verbinden.');
        default:
          throw DriveException('Anmeldung fehlgeschlagen: ${j['error_description'] ?? j['error'] ?? r.statusCode}');
      }
    }
    throw DriveException('Der Code ist abgelaufen – bitte erneut verbinden.');
  }

  Future<String> _token() async {
    final c = cfg;
    if (c?.refreshToken == null) throw DriveException('Google Drive ist nicht verbunden.');
    if (_accessToken != null && DateTime.now().isBefore(_accessExpires)) return _accessToken!;
    final r = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'client_id': c!.clientId,
      'client_secret': c.clientSecret,
      'refresh_token': c.refreshToken!,
      'grant_type': 'refresh_token',
    }).timeout(const Duration(seconds: 30));
    final j = _decode(r);
    if (r.statusCode != 200) {
      if (j['error'] == 'invalid_grant') {
        throw DriveException('Google-Anmeldung abgelaufen oder widerrufen – Drive-Abgleich bitte neu verbinden.');
      }
      throw DriveException('Token-Fehler: ${j['error_description'] ?? j['error'] ?? r.statusCode}');
    }
    _accessToken = j['access_token'] as String;
    _accessExpires = DateTime.now().add(Duration(seconds: ((j['expires_in'] as num?)?.toInt() ?? 3600) - 60));
    return _accessToken!;
  }

  Future<Map<String, String>> _auth() async => {'Authorization': 'Bearer ${await _token()}'};

  // ---------------- Drive-Dateioperationen ----------------

  /// Sucht die Sync-Datei. Rückgabe: (id, modifiedTime) oder null.
  Future<(String, String)?> findFile() async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'drive',
      'q': "name = '$fileName' and trashed = false",
      'fields': 'files(id,modifiedTime)',
      'orderBy': 'modifiedTime desc',
      'pageSize': '5',
    });
    final r = await http.get(uri, headers: await _auth()).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw DriveException('Drive-Fehler ${r.statusCode}: ${_decode(r)['error']?['message'] ?? ''}');
    final files = (_decode(r)['files'] as List?) ?? [];
    if (files.isEmpty) return null;
    final f = files.first as Map;
    return (f['id'] as String, f['modifiedTime'] as String? ?? '');
  }

  /// Ordner „EchoWP-Mail“ suchen oder anlegen (nur von der App selbst angelegte sind sichtbar).
  Future<String> _folderId() async {
    final uri = Uri.https('www.googleapis.com', '/drive/v3/files', {
      'spaces': 'drive',
      'q': "name = '$folderName' and mimeType = '$_folderMime' and trashed = false",
      'fields': 'files(id)',
      'pageSize': '1',
    });
    final r = await http.get(uri, headers: await _auth()).timeout(const Duration(seconds: 30));
    final files = (_decode(r)['files'] as List?) ?? [];
    if (r.statusCode == 200 && files.isNotEmpty) return (files.first as Map)['id'] as String;
    final c = await http
        .post(
          Uri.parse('https://www.googleapis.com/drive/v3/files?fields=id'),
          headers: {...await _auth(), 'Content-Type': 'application/json'},
          body: jsonEncode({'name': folderName, 'mimeType': _folderMime}),
        )
        .timeout(const Duration(seconds: 30));
    if (c.statusCode != 200) throw DriveException('Ordner konnte nicht angelegt werden (${c.statusCode}).');
    return _decode(c)['id'] as String;
  }

  Future<Uint8List> download(String id) async {
    final r = await http
        .get(Uri.parse('https://www.googleapis.com/drive/v3/files/$id?alt=media'), headers: await _auth())
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw DriveException('Download fehlgeschlagen (${r.statusCode}).');
    return r.bodyBytes;
  }

  /// Lädt hoch (neu oder überschreibend). Rückgabe: (id, modifiedTime).
  Future<(String, String)> upload(Uint8List bytes, {String? id}) async {
    final headers = await _auth();
    http.Response r;
    if (id != null) {
      r = await http
          .patch(
            Uri.parse('https://www.googleapis.com/upload/drive/v3/files/$id?uploadType=media&fields=id,modifiedTime'),
            headers: {...headers, 'Content-Type': 'application/octet-stream'},
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      if (r.statusCode == 404) return upload(bytes);
    } else {
      const boundary = 'echowp_mail_boundary_7f3a';
      final meta = jsonEncode({
        'name': fileName,
        'parents': [await _folderId()],
        'description': 'Verschlüsselte Einstellungen von EchoWP-Mail – nicht löschen.',
      });
      final body = BytesBuilder()
        ..add(utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'
            '--$boundary\r\nContent-Type: application/octet-stream\r\n\r\n'))
        ..add(bytes)
        ..add(utf8.encode('\r\n--$boundary--'));
      r = await http
          .post(
            Uri.parse('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,modifiedTime'),
            headers: {...headers, 'Content-Type': 'multipart/related; boundary=$boundary'},
            body: body.toBytes(),
          )
          .timeout(const Duration(seconds: 60));
    }
    if (r.statusCode != 200) {
      throw DriveException('Upload fehlgeschlagen (${r.statusCode}): ${_decode(r)['error']?['message'] ?? ''}');
    }
    final j = _decode(r);
    return (j['id'] as String, j['modifiedTime'] as String? ?? '');
  }
}

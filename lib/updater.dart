import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Version dieser App – muss zu `version:` in pubspec.yaml passen (Test prüft das).
const appVersion = '6.3.0';

/// Build-Nummer (GitHub-Lauf), wird beim Bauen per `--dart-define=ECHOWP_BUILD=…` gesetzt.
const appBuild = int.fromEnvironment('ECHOWP_BUILD');

/// Kurzform für die Anzeige: 6.2.0 → 6.2, 6.2.1 bleibt.
String shortVersion(String v) => v.endsWith('.0') && v.split('.').length == 3 ? v.substring(0, v.length - 2) : v;

class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => message;
}

class ReleaseAsset {
  final String name;
  final String url;
  final int size;

  /// SHA-256 (hex, klein), falls GitHub sie mitliefert.
  final String? sha256;
  const ReleaseAsset({required this.name, required this.url, required this.size, this.sha256});
}

class ReleaseInfo {
  final String tag;
  final String version; // z. B. 6.2.0
  final int build; // GitHub-Lauf aus dem Tag (…-build-53)
  final String pageUrl;
  final Map<String, ReleaseAsset> assets;
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.build,
    required this.pageUrl,
    required this.assets,
  });

  String get label => 'v${shortVersion(version)} (Build $build)';
}

/// Sucht neue Versionen auf GitHub (öffentliches Repo, ohne Anmeldung) und installiert sie.
class Updater {
  static const repo = 'EchoWP-Design/echowp-mail';
  static const _api = 'https://api.github.com/repos/$repo/releases/latest';

  /// Nur Android und Windows haben eigene Pakete.
  static bool get supported => Platform.isAndroid || Platform.isWindows;

  final http.Client Function() _client;
  Updater({http.Client Function()? client}) : _client = client ?? http.Client.new;

  // ------------------------------------------------------------ Auswerten

  static final _tagRe = RegExp(r'^v(\d+\.\d+\.\d+)(?:-build-(\d+))?$');

  static ReleaseInfo? parse(Map<String, dynamic> j) {
    if (j['draft'] == true || j['prerelease'] == true) return null;
    final tag = j['tag_name'] as String? ?? '';
    final m = _tagRe.firstMatch(tag);
    if (m == null) return null;
    final assets = <String, ReleaseAsset>{};
    for (final a in (j['assets'] as List? ?? const [])) {
      if (a is! Map) continue;
      final name = a['name'] as String?;
      final url = a['browser_download_url'] as String?;
      if (name == null || url == null) continue;
      final digest = a['digest'] as String?;
      assets[name] = ReleaseAsset(
        name: name,
        url: url,
        size: (a['size'] as num?)?.toInt() ?? 0,
        sha256: digest != null && digest.startsWith('sha256:') ? digest.substring(7).toLowerCase() : null,
      );
    }
    return ReleaseInfo(
      tag: tag,
      version: m.group(1)!,
      build: int.tryParse(m.group(2) ?? '') ?? 0,
      pageUrl: j['html_url'] as String? ?? 'https://github.com/$repo/releases/latest',
      assets: assets,
    );
  }

  /// -1 / 0 / 1 wie compareTo, für „6.10.0“ > „6.9.3“.
  static int compareVersions(String a, String b) {
    final x = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final y = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
      if (d != 0) return d.sign;
    }
    return 0;
  }

  /// Neuer als die laufende App? Gleiche Version zählt nur, wenn der Build neuer ist
  /// (und die eigene Build-Nummer bekannt ist).
  static bool isNewer(ReleaseInfo r, {String current = appVersion, int build = appBuild}) {
    final c = compareVersions(r.version, current);
    if (c != 0) return c > 0;
    return build > 0 && r.build > build;
  }

  /// Passende Datei für dieses Gerät. [platform] / [dartVersion] nur für Tests.
  static String? assetFor({String? platform, String? dartVersion}) {
    final p = platform ?? Platform.operatingSystem;
    if (p == 'windows') return 'EchoWP-Mail-Setup.exe';
    if (p != 'android') return null;
    // Platform.version endet z. B. mit: on "android_arm64" bzw. "android_arm"
    final v = dartVersion ?? Platform.version;
    if (v.contains('android_arm64')) return 'EchoWP-Mail.apk';
    if (v.contains('android_arm"') || v.contains('android_arm ')) return 'EchoWP-Mail-alte-Geraete-32bit.apk';
    return 'EchoWP-Mail.apk';
  }

  // ------------------------------------------------------------ Abfragen

  Future<ReleaseInfo?> latest() async {
    final c = _client();
    try {
      final r = await c.get(Uri.parse(_api), headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'EchoWP-Mail/$appVersion',
      }).timeout(const Duration(seconds: 20));
      if (r.statusCode == 404) return null; // noch kein Release
      if (r.statusCode == 403 || r.statusCode == 429) {
        throw UpdateException('GitHub lässt gerade keine Abfrage zu – später erneut versuchen.');
      }
      if (r.statusCode != 200) throw UpdateException('Update-Prüfung fehlgeschlagen (HTTP ${r.statusCode}).');
      return parse(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
    } on SocketException {
      throw UpdateException('Keine Internetverbindung – Update-Prüfung nicht möglich.');
    } on http.ClientException {
      throw UpdateException('Keine Verbindung zu GitHub – Update-Prüfung nicht möglich.');
    } on TimeoutException {
      throw UpdateException('GitHub antwortet nicht – später erneut versuchen.');
    } finally {
      c.close();
    }
  }

  /// Prüfsumme aus SHA256SUMS.txt, falls GitHub keine mitliefert.
  Future<String?> _sumFromList(ReleaseInfo r, String name) async {
    final list = r.assets['SHA256SUMS.txt'];
    if (list == null) return null;
    final c = _client();
    try {
      final resp = await c.get(Uri.parse(list.url)).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return null;
      for (final line in const LineSplitter().convert(resp.body)) {
        final m = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(line.trim());
        if (m != null && m.group(2)!.trim() == name) return m.group(1)!.toLowerCase();
      }
      return null;
    } finally {
      c.close();
    }
  }

  // ------------------------------------------------------------ Herunterladen

  /// Lädt die passende Datei, prüft Größe und SHA-256. [progress] 0..1.
  /// [into] = Zielordner (Standard: Cache der App).
  Future<File> download(ReleaseInfo r, String assetName,
      {void Function(double)? progress, Directory? into}) async {
    final asset = r.assets[assetName];
    if (asset == null) throw UpdateException('Im Release fehlt die Datei $assetName.');
    final expected = asset.sha256 ?? await _sumFromList(r, assetName);
    if (expected == null) {
      throw UpdateException('Für $assetName gibt es keine Prüfsumme – Update aus Sicherheitsgründen abgebrochen.');
    }
    final base = into ?? await getTemporaryDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$assetName');

    final c = _client();
    final out = file.openWrite();
    final sink = Sha256().newHashSink();
    var done = 0;
    try {
      final resp = await c.send(http.Request('GET', Uri.parse(asset.url))).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) throw UpdateException('Download fehlgeschlagen (HTTP ${resp.statusCode}).');
      final total = resp.contentLength ?? asset.size;
      await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
        out.add(chunk);
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) progress?.call((done / total).clamp(0, 1).toDouble());
      }
    } on SocketException {
      throw UpdateException('Download abgebrochen – Internetverbindung prüfen.');
    } on http.ClientException {
      throw UpdateException('Download abgebrochen – Internetverbindung prüfen.');
    } on TimeoutException {
      throw UpdateException('Download hängt – später erneut versuchen.');
    } finally {
      await out.close();
      c.close();
    }
    sink.close();
    final hex = (await sink.hash()).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if ((asset.size > 0 && done != asset.size) || hex != expected) {
      await file.delete().catchError((_) => file);
      throw UpdateException('Die heruntergeladene Datei ist beschädigt (Prüfsumme falsch) – bitte erneut versuchen.');
    }
    return file;
  }

  // ------------------------------------------------------------ Installieren

  /// Windows: wurde die App per Installer eingerichtet (nicht die portable ZIP)?
  static bool get windowsInstalled {
    final dir = File(Platform.resolvedExecutable).parent.path;
    return File('$dir\\unins000.exe').existsSync();
  }

  /// Windows: startet den Installer still, beendet die App; der Installer startet sie neu.
  /// (Android lädt über den Browser – eine eigene Installationsberechtigung
  /// lässt Play Protect die App als schädlich blockieren.)
  Future<void> install(File f) async {
    if (Platform.isWindows) {
      await Process.start(
        f.path,
        const ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/UPDATE=1'],
        mode: ProcessStartMode.detached,
      );
      // Dateien sind sonst gesperrt – der Installer startet die App danach neu
      await Future.delayed(const Duration(milliseconds: 500));
      exit(0);
    }
    throw UpdateException('Updates werden auf diesem System nicht unterstützt.');
  }
}

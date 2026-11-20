import 'package:shared_preferences/shared_preferences.dart';

/// Merkt sich je Konto und Ordner die UIDs neu eingetroffener Mails.
///
/// „Neu“ = seit dem letzten Öffnen des Ordners per Synchronisierung eingetroffen und noch
/// nicht gelesen/gelöscht. Gespeichert in SharedPreferences, damit App, Push-Dienst und
/// Hintergrundabruf (eigene Isolate) denselben Stand teilen.
class NewMailStore {
  static const prefix = 'newuids_';
  static const _max = 500;

  static String key(String accountId, String path) => '$prefix$accountId|$path';

  static Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p;
  }

  static Set<int> _read(SharedPreferences p, String k) =>
      (p.getStringList(k) ?? const <String>[]).map(int.tryParse).whereType<int>().toSet();

  static Future<void> _write(SharedPreferences p, String k, Set<int> uids) async {
    if (uids.isEmpty) {
      await p.remove(k);
      return;
    }
    final list = uids.toList()..sort();
    final trimmed = list.length > _max ? list.sublist(list.length - _max) : list;
    await p.setStringList(k, trimmed.map((u) => '$u').toList());
  }

  static Future<void> add(String accountId, String path, Iterable<int> uids) async {
    if (uids.isEmpty) return;
    final p = await _prefs();
    final k = key(accountId, path);
    await _write(p, k, _read(p, k)..addAll(uids));
  }

  static Future<void> remove(String accountId, String path, Iterable<int> uids) async {
    if (uids.isEmpty) return;
    final p = await _prefs();
    final k = key(accountId, path);
    final cur = _read(p, k);
    if (!cur.any(uids.contains)) return;
    await _write(p, k, cur..removeAll(uids));
  }

  static Future<void> clear(String accountId, String path) async {
    final p = await _prefs();
    await p.remove(key(accountId, path));
  }

  static Future<void> clearAccount(String accountId) async {
    final p = await _prefs();
    for (final k in p.getKeys().where((k) => k.startsWith('$prefix$accountId|')).toList()) {
      await p.remove(k);
    }
  }

  /// Konto → Ordnerpfad → UIDs
  static Future<Map<String, Map<String, Set<int>>>> loadAll() async {
    final p = await _prefs();
    final out = <String, Map<String, Set<int>>>{};
    for (final k in p.getKeys().where((k) => k.startsWith(prefix))) {
      final rest = k.substring(prefix.length);
      final sep = rest.indexOf('|');
      if (sep <= 0) continue;
      final uids = _read(p, k);
      if (uids.isEmpty) continue;
      (out[rest.substring(0, sep)] ??= {})[rest.substring(sep + 1)] = uids;
    }
    return out;
  }
}

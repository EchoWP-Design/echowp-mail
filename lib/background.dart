import 'dart:io';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'mail_service.dart';
import 'models.dart';
import 'new_mail.dart';
import 'notifications.dart';
import 'storage.dart';
import 'tags.dart';

const _taskName = 'echowp-mailcheck';

/// Einstiegspunkt für den Android-Hintergrundabruf (läuft auch bei geschlossener App).
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await MailCheck.runOnce(fromBackground: true);
    } catch (_) {}
    return true; // nie als Fehler melden, sonst plant Android Wiederholungen
  });
}

class MailCheck {
  /// Gemeinsamer Stand (App, Hintergrundabruf, Push-Dienst) → keine doppelten Benachrichtigungen.
  static String uidKey(String accountId, [String path = 'INBOX']) =>
      path == 'INBOX' ? 'uidnext_$accountId' : 'uidnext_$accountId|$path';

  /// Ordner, die regelmäßig geprüft werden (Automatik; Push zusätzlich als Rückfallebene).
  static List<String> polledFolders(EchoAccount a) =>
      [...a.foldersWith(SyncMode.push), ...a.foldersWith(SyncMode.auto)];

  static Future<void> schedule({required int minutes, required bool enabled}) async {
    if (!Platform.isAndroid) return;
    try {
      final wm = Workmanager();
      await wm.initialize(callbackDispatcher);
      if (!enabled || minutes <= 0) {
        await wm.cancelByUniqueName(_taskName);
        return;
      }
      await wm.registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: Duration(minutes: max(15, minutes)), // Android-Minimum: 15 Minuten
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      );
    } catch (_) {}
  }

  /// Prüft einen Ordner auf neue Mails, merkt den Stand und benachrichtigt (falls eingestellt).
  /// Gibt die neuen ungelesenen Mails zurück (leer beim allerersten Abruf).
  static Future<List<MailItem>> checkFolder(
    AccountConnection conn,
    EchoAccount a,
    String path,
    AppSettings settings,
  ) async {
    final key = uidKey(a.id, path);
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final last = prefs.getInt(key);
    final (next, news) = await conn.checkNew(last, path: path);
    await prefs.reload();
    final current = prefs.getInt(key);
    final alreadyHandled = current != null && current >= next;
    if (!alreadyHandled) await prefs.setInt(key, next);
    if (last == null) return const [];
    if (!alreadyHandled && news.isNotEmpty) {
      // Für den „neu“-Zähler hinter Konto und Ordner vormerken
      await NewMailStore.add(a.id, path, news.map((n) => n.uid));
      // Tag-Regeln: Keyword (Gmail zusätzlich Label) auf dem Server setzen.
      // Ein Fehler hier darf die Benachrichtigung nicht verhindern.
      try {
        await applyTags(conn, a, path, news, settings.tagRules);
      } catch (_) {}
      if (settings.notifications && a.syncOf(path).notify) {
        await Notifier.notifyNew(a, path, news);
      }
    }
    return news;
  }

  /// Setzt die Tags laut [rules] auf [items] (Server und lokal). Liefert die Zahl der
  /// gesetzten Tags (je Mail und Tag einer).
  static Future<int> applyTags(
    AccountConnection conn,
    EchoAccount a,
    String path,
    List<MailItem> items,
    List<TagRule> rules,
  ) async {
    var n = 0;
    for (final e in tagPlan(items, a.id, rules).entries) {
      final (label, uids) = e.value;
      final stored = await conn.addTag(path, uids, e.key, gmailLabel: a.isGmail ? gmailLabelFor(label) : null);
      if (stored) {
        for (final m in items) {
          if (uids.contains(m.uid)) m.keywords.add(e.key);
        }
      }
      // Ohne Keyword-Unterstützung zählt bei Gmail das Label, sonst ist nichts passiert
      if (stored || a.isGmail) n += uids.length;
    }
    return n;
  }

  /// Prüft alle automatisch synchronisierten Ordner aller Konten einmal.
  static Future<void> runOnce({bool fromBackground = false}) async {
    final storage = Storage();
    final settings = await storage.loadSettings();
    if (settings.pollMinutes <= 0) return;
    final accounts = await storage.loadAccounts();
    if (accounts.isEmpty) return;
    await Notifier.init(requestPermission: !fromBackground);
    for (final a in accounts) {
      final conn = AccountConnection(a);
      try {
        for (final path in polledFolders(a)) {
          try {
            await checkFolder(conn, a, path, settings);
          } catch (_) {}
        }
      } finally {
        await conn.close();
      }
    }
  }
}

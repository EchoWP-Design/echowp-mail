import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:enough_mail/enough_mail.dart' as em;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'background.dart';

import 'mail_service.dart';
import 'models.dart';
import 'new_mail.dart';
import 'storage.dart';

/// Aktions-IDs der Benachrichtigungsknöpfe (Android).
class NotifyAction {
  static const read = 'read';
  static const delete = 'delete';
  static const reply = 'reply';
}

/// Inhalt einer Mail-Benachrichtigung (als JSON im Payload).
class NotifyPayload {
  final String accountId;
  final String path;
  final List<int> uids;
  const NotifyPayload(this.accountId, this.path, this.uids);

  String encode() => jsonEncode({'a': accountId, 'p': path, 'u': uids});

  static NotifyPayload? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      final uids = (j['u'] as List).map((e) => (e as num).toInt()).toList();
      if (uids.isEmpty) return null;
      return NotifyPayload(j['a'] as String, j['p'] as String, uids);
    } catch (_) {
      return null;
    }
  }
}

/// Wird aufgerufen, wenn „Löschen“ oder „Als gelesen“ gedrückt wurde – auch bei geschlossener App
/// (eigenes Hintergrund-Isolat, darum ohne AppState).
///
/// Android startet dafür nur einen kurzen Broadcast-Empfänger. Läuft kein Push-Dienst, darf
/// das System den Prozess sofort einfrieren oder beenden (HyperOS/MIUI tut das sehr schnell) –
/// dann kam der IMAP-Befehl nie beim Server an. Deshalb wird die Aktion zuerst dauerhaft
/// vorgemerkt und zusätzlich ein WorkManager-Auftrag geplant, der sie sicher nachholt.
@pragma('vm:entry-point')
Future<void> notificationActionBackground(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  final p = NotifyPayload.decode(r.payload);
  final action = r.actionId;
  if (p == null || !PendingActions.handles(action)) return;
  await PendingActions.add(action!, p);
  await PendingActions.scheduleWorker();
  await PendingActions.process();
}

/// Vorgemerkte Benachrichtigungs-Aktionen (Löschen / Als gelesen). Gespeichert in
/// SharedPreferences, damit App, Push-Dienst, Hintergrundabruf und Aktions-Isolat sie teilen.
class PendingActions {
  static const key = 'pending_notify_actions';
  static const workerName = 'echowp-notify-action';

  /// Nach dieser Zeit wird eine Aktion aufgegeben (mit Hinweis).
  static const maxAge = Duration(hours: 24);

  /// Name des Ports, über den die laufende App von erledigten Aktionen erfährt.
  static const portName = 'echowp_notify_action_done';

  static bool handles(String? action) => action == NotifyAction.read || action == NotifyAction.delete;

  static Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p;
  }

  static List<Map<String, dynamic>> _read(SharedPreferences p) {
    final out = <Map<String, dynamic>>[];
    for (final s in p.getStringList(key) ?? const <String>[]) {
      try {
        out.add(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
    return out;
  }

  static Future<void> _write(SharedPreferences p, List<Map<String, dynamic>> list) async {
    if (list.isEmpty) {
      await p.remove(key);
    } else {
      await p.setStringList(key, list.map(jsonEncode).toList());
    }
  }

  static String _id(Map<String, dynamic> e) => '${e['x']}|${e['a']}|${e['p']}|${(e['u'] as List).join(',')}';

  static Future<void> add(String action, NotifyPayload p) async {
    final prefs = await _prefs();
    final list = _read(prefs);
    final e = {'x': action, 'a': p.accountId, 'p': p.path, 'u': p.uids, 't': DateTime.now().millisecondsSinceEpoch};
    if (list.any((o) => _id(o) == _id(e))) return;
    list.add(e);
    await _write(prefs, list);
  }

  static Future<int> count() async => _read(await _prefs()).length;

  /// Auftrag für WorkManager (Android): holt offene Aktionen nach, sobald Netz da ist –
  /// auch wenn der Prozess des Aktions-Isolats inzwischen eingefroren oder beendet wurde.
  static Future<void> scheduleWorker() async {
    if (!Platform.isAndroid) return;
    try {
      final wm = Workmanager();
      await wm.initialize(callbackDispatcher);
      await wm.registerOneOffTask(
        workerName,
        workerName,
        initialDelay: const Duration(seconds: 20),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
    } catch (_) {}
  }

  static bool _busy = false;

  /// Führt alle vorgemerkten Aktionen aus. Liefert true, wenn danach nichts mehr offen ist.
  /// [run] ist austauschbar (Tests).
  static Future<bool> process({Future<bool> Function(String action, NotifyPayload p)? run}) async {
    if (_busy) return false;
    _busy = true;
    try {
      final prefs = await _prefs();
      final todo = _read(prefs);
      if (todo.isEmpty) return true;
      final done = <String>{};
      final expired = <Map<String, dynamic>>[];
      for (final e in todo) {
        final NotifyPayload p;
        try {
          p = NotifyPayload(e['a'] as String, e['p'] as String,
              (e['u'] as List).map((u) => (u as num).toInt()).toList());
        } catch (_) {
          done.add(_id(e));
          continue;
        }
        final action = e['x'] as String? ?? '';
        final ok = await (run ?? Notifier.runAction)(action, p);
        if (ok) {
          done.add(_id(e));
          _tellApp(action, p);
        } else {
          final t = DateTime.fromMillisecondsSinceEpoch((e['t'] as num?)?.toInt() ?? 0);
          if (DateTime.now().difference(t) > maxAge) expired.add(e);
        }
      }
      // Neu lesen: andere Isolate können inzwischen etwas vorgemerkt haben
      final fresh = await _prefs();
      final gone = {...done, ...expired.map(_id)};
      final rest = _read(fresh).where((e) => !gone.contains(_id(e))).toList();
      await _write(fresh, rest);
      for (final e in expired) {
        await Notifier.show(Notifier._id(), 'Aktion nicht ausgeführt',
            e['x'] == NotifyAction.delete
                ? 'Eine Mail konnte nicht gelöscht werden (Server nicht erreichbar). Bitte in der App löschen.'
                : 'Eine Mail konnte nicht als gelesen markiert werden. Bitte in der App erledigen.');
      }
      return rest.isEmpty;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }

  /// Meldet der laufenden App (anderes Isolat im selben Prozess), dass eine Aktion erledigt ist.
  static void _tellApp(String action, NotifyPayload p) {
    try {
      IsolateNameServer.lookupPortByName(portName)?.send(jsonEncode({'x': action, ...(jsonDecode(p.encode()) as Map<String, dynamic>)}));
    } catch (_) {}
  }

  static ReceivePort? _port;

  /// In der App aufrufen: [onDone] erfährt von Aktionen, die andere Isolate erledigt haben.
  static void listen(void Function(String action, NotifyPayload p) onDone) {
    if (_port != null) return;
    try {
      final port = ReceivePort();
      IsolateNameServer.removePortNameMapping(portName);
      IsolateNameServer.registerPortWithName(port.sendPort, portName);
      port.listen((msg) {
        try {
          final j = jsonDecode(msg as String) as Map<String, dynamic>;
          final p = NotifyPayload.decode(jsonEncode(j));
          if (p != null) onDone(j['x'] as String, p);
        } catch (_) {}
      });
      _port = port;
    } catch (_) {}
  }
}

class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static final _taps = StreamController<NotificationResponse>.broadcast();

  /// Antippen der Benachrichtigung bzw. „Antworten“ (öffnet die App).
  static Stream<NotificationResponse> get taps => _taps.stream;

  static Future<void> init({bool requestPermission = true}) async {
    if (_ready) return;
    if (!Platform.isAndroid && !Platform.isWindows) return;
    try {
      // Weiße Silhouette (tool/android_res) – das farbige App-Symbol erscheint in der
      // Statusleiste sonst als schwarzes Viereck
      const android = AndroidInitializationSettings(statusIcon);
      final windows = WindowsInitializationSettings(
        appName: 'EchoWP-Mail',
        appUserModelId: 'EchoWP.Mail',
        guid: 'f2b6c8e4-3d1a-4b7e-9c2f-5a8d7e6b1c30',
      );
      await _plugin.initialize(
        InitializationSettings(android: android, windows: windows),
        onDidReceiveNotificationResponse: (r) {
          if (PendingActions.handles(r.actionId)) {
            final p = NotifyPayload.decode(r.payload);
            (p == null ? Future.value() : PendingActions.add(r.actionId!, p).then((_) => PendingActions.process()))
                .whenComplete(() => _taps.add(r));
          } else {
            _taps.add(r);
          }
        },
        onDidReceiveBackgroundNotificationResponse: notificationActionBackground,
      );
      if (Platform.isAndroid && requestPermission) {
        await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Hat eine Benachrichtigung die App gestartet? (Antippen / „Antworten“ bei geschlossener App)
  static Future<NotificationResponse?> launchResponse() async {
    if (!_ready) return null;
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      return (d?.didNotificationLaunchApp ?? false) ? d!.notificationResponse : null;
    } catch (_) {
      return null;
    }
  }

  /// Symbol in der Statusleiste (Android-Ressource drawable/ic_stat_echowp).
  static const statusIcon = 'ic_stat_echowp';

  /// EchoWP-Gelb für Symbol und Akzent der Benachrichtigung.
  static const accent = Color(0xFFFFD400);

  static int _id() => DateTime.now().millisecondsSinceEpoch.remainder(1 << 30);

  /// Knöpfe unter der Benachrichtigung (nur Android). „Antworten“ nur bei einzelner Mail.
  static List<AndroidNotificationAction> actionsFor({required bool single}) => [
        const AndroidNotificationAction(NotifyAction.delete, 'Löschen'),
        const AndroidNotificationAction(NotifyAction.read, 'Als gelesen markieren'),
        if (single) const AndroidNotificationAction(NotifyAction.reply, 'Antworten', showsUserInterface: true),
      ];

  static Future<void> show(int id, String title, String body,
      {NotifyPayload? payload, bool single = true}) async {
    if (!_ready) return;
    try {
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          'new_mail',
          'Neue E-Mails',
          channelDescription: 'Benachrichtigung bei neuen E-Mails',
          importance: Importance.high,
          priority: Priority.high,
          // Auf dem gesperrten Bildschirm nur „Neue E-Mail“, ohne Absender/Betreff
          visibility: NotificationVisibility.private,
          icon: statusIcon,
          color: accent,
          actions: payload == null ? null : actionsFor(single: single),
        ),
        windows: const WindowsNotificationDetails(),
      );
      await _plugin.show(id, title, body, details, payload: payload?.encode());
    } catch (_) {}
  }

  static Future<void> notifyNew(EchoAccount a, String path, List<MailItem> news) async {
    if (news.isEmpty) return;
    if (news.length <= 3) {
      for (final n in news) {
        await show(_id(), n.sender, n.subject, payload: NotifyPayload(a.id, path, [n.uid]));
      }
    } else {
      await show(_id(), '${news.length} neue E-Mails', a.email,
          payload: NotifyPayload(a.id, path, news.map((n) => n.uid).toList()), single: false);
    }
  }

  /// Führt „Löschen“ bzw. „Als gelesen markieren“ direkt auf dem Server aus.
  /// Nicht direkt aufrufen – über [PendingActions] (vormerken, dann ausführen).
  static Future<bool> runAction(String? action, NotifyPayload? p) async {
    if (p == null || !PendingActions.handles(action)) return false;
    final accounts = await Storage().loadAccounts();
    EchoAccount? acc;
    for (final a in accounts) {
      if (a.id == p.accountId) acc = a;
    }
    if (acc == null) return true; // Konto entfernt → nichts mehr zu tun
    final conn = AccountConnection(acc);
    try {
      if (action == NotifyAction.read) {
        await conn.setFlag(p.path, p.uids, em.MessageFlags.seen, true);
      } else {
        final folders = await conn.listFolders();
        String? trash;
        for (final f in folders) {
          if (f.role == 'trash' && f.selectable) trash ??= f.path;
        }
        await conn.delete(p.path, p.uids, trash);
      }
      await NewMailStore.remove(p.accountId, p.path, p.uids);
      return true;
    } catch (_) {
      return false;
    } finally {
      await conn.close();
    }
  }
}

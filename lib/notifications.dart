import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:enough_mail/enough_mail.dart' as em;
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
@pragma('vm:entry-point')
Future<void> notificationActionBackground(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier.runAction(r.actionId, NotifyPayload.decode(r.payload));
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
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      final windows = WindowsInitializationSettings(
        appName: 'EchoWP-Mail',
        appUserModelId: 'EchoWP.Mail',
        guid: 'f2b6c8e4-3d1a-4b7e-9c2f-5a8d7e6b1c30',
      );
      await _plugin.initialize(
        InitializationSettings(android: android, windows: windows),
        onDidReceiveNotificationResponse: (r) {
          if (r.actionId == NotifyAction.read || r.actionId == NotifyAction.delete) {
            runAction(r.actionId, NotifyPayload.decode(r.payload)).then((_) => _taps.add(r));
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
  static Future<bool> runAction(String? action, NotifyPayload? p) async {
    if (p == null || (action != NotifyAction.read && action != NotifyAction.delete)) return false;
    final accounts = await Storage().loadAccounts();
    EchoAccount? acc;
    for (final a in accounts) {
      if (a.id == p.accountId) acc = a;
    }
    if (acc == null) return false;
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

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';

class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

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
      await _plugin.initialize(InitializationSettings(android: android, windows: windows));
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

  static int _id() => DateTime.now().millisecondsSinceEpoch.remainder(1 << 30);

  static Future<void> show(int id, String title, String body) async {
    if (!_ready) return;
    try {
      final details = NotificationDetails(
        android: const AndroidNotificationDetails(
          'new_mail',
          'Neue E-Mails',
          channelDescription: 'Benachrichtigung bei neuen E-Mails',
          importance: Importance.high,
          priority: Priority.high,
          // Auf dem gesperrten Bildschirm nur „Neue E-Mail“, ohne Absender/Betreff
          visibility: NotificationVisibility.private,
        ),
        windows: WindowsNotificationDetails(),
      );
      await _plugin.show(id, title, body, details);
    } catch (_) {}
  }

  static Future<void> notifyNew(String accountEmail, List<MailItem> news) async {
    if (news.isEmpty) return;
    if (news.length <= 3) {
      for (final n in news) {
        await show(_id(), n.sender, n.subject);
      }
    } else {
      await show(_id(), '${news.length} neue E-Mails', accountEmail);
    }
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:enough_mail/enough_mail.dart' as em;
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'background.dart';
import 'mail_service.dart';
import 'models.dart';
import 'notifications.dart';
import 'storage.dart';

typedef PushChange = Future<void> Function(EchoAccount account, String path);

/// Hält eine IMAP-IDLE-Verbindung für genau einen Ordner offen und meldet neue Mails.
class PushWatcher {
  final EchoAccount account;
  final String path;
  final PushChange onChange;
  bool _stopped = false;
  em.ImapClient? _client;
  StreamSubscription<em.ImapEvent>? _sub;
  Completer<void>? _wake;
  Timer? _debounce;

  PushWatcher(this.account, this.path, this.onChange);

  String get key => '${account.id}|$path';

  void start() => _loop();

  Future<void> stop() async {
    _stopped = true;
    _wake?.complete();
    await _close();
  }

  Future<void> _close() async {
    await _sub?.cancel();
    _sub = null;
    final c = _client;
    _client = null;
    if (c != null) {
      try {
        await c.idleDone().timeout(const Duration(seconds: 5));
      } catch (_) {}
      try {
        await c.logout().timeout(const Duration(seconds: 5));
      } catch (_) {}
      try {
        await c.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _loop() async {
    var backoff = 5;
    while (!_stopped) {
      try {
        await _session();
        backoff = 5;
      } catch (_) {
        await _close();
        if (_stopped) break;
        await Future.delayed(Duration(seconds: backoff));
        backoff = min(backoff * 2, 300); // max. 5 Minuten zwischen Wiederholungen
      }
    }
  }

  Future<void> _session() async {
    final c = await openImap(account);
    _client = c;
    await selectFolder(c, path);
    final lost = Completer<void>();
    _sub = c.eventBus.on<em.ImapEvent>().listen((e) {
      if (e is em.ImapMessagesExistEvent && e.newMessagesExists > e.oldMessagesExists) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 2), () => onChange(account, path));
      } else if (e.eventType == em.ImapEventType.connectionLost && !lost.isCompleted) {
        lost.complete();
      }
    });
    // Beim (Wieder-)Verbinden einmal prüfen – evtl. kam während der Pause etwas an.
    unawaited(onChange(account, path));
    await c.idleStart();
    while (!_stopped && !lost.isCompleted) {
      _wake = Completer<void>();
      // IDLE alle 20 Minuten erneuern (Server trennen nach spätestens 29 Minuten).
      await Future.any([lost.future, _wake!.future, Future.delayed(const Duration(minutes: 20))]);
      if (_stopped) return;
      if (lost.isCompleted) throw const SocketException('Verbindung verloren');
      await c.idleDone().timeout(const Duration(seconds: 30));
      await c.noop().timeout(const Duration(seconds: 30));
      await c.idleStart();
    }
    if (lost.isCompleted) throw const SocketException('Verbindung verloren');
  }
}

/// Verwaltet alle Push-Verbindungen (je Konto und Push-Ordner eine).
class PushEngine {
  final PushChange onChange;
  final Map<String, PushWatcher> _watchers = {};
  PushEngine(this.onChange);

  int get activeCount => _watchers.length;

  /// Startet/stoppt Verbindungen passend zu den Kontoeinstellungen.
  Future<void> apply(List<EchoAccount> accounts) async {
    final wanted = <String, (EchoAccount, String)>{};
    for (final a in accounts) {
      for (final p in a.foldersWith(SyncMode.push).take(maxPushFoldersPerAccount)) {
        wanted['${a.id}|$p'] = (a, p);
      }
    }
    for (final k in _watchers.keys.toList()) {
      final w = _watchers[k]!;
      final want = wanted[k];
      // Neu starten, wenn sich Zugangsdaten geändert haben
      if (want == null || want.$1.toJson().toString() != w.account.toJson().toString()) {
        await _watchers.remove(k)!.stop();
      }
    }
    for (final e in wanted.entries) {
      if (_watchers.containsKey(e.key)) continue;
      final w = PushWatcher(e.value.$1, e.value.$2, onChange);
      _watchers[e.key] = w;
      w.start();
    }
  }

  Future<void> stopAll() async {
    for (final w in _watchers.values) {
      await w.stop();
    }
    _watchers.clear();
  }
}

// ---------------------------------------------------------------- Android-Vordergrunddienst

const _channelId = 'push_service';
const _serviceNotificationId = 4711;

/// Läuft in einem eigenen Isolat im Android-Vordergrunddienst – auch bei geschlossener App.
@pragma('vm:entry-point')
Future<void> pushServiceMain(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier.init(requestPermission: false);
  final storage = Storage();
  var settings = await storage.loadSettings();
  final conns = <String, AccountConnection>{};

  final engine = PushEngine((a, path) async {
    final conn = conns.putIfAbsent('${a.id}|$path', () => AccountConnection(a));
    conn.account = a;
    try {
      final news = await MailCheck.checkFolder(conn, a, path, settings);
      if (news.isNotEmpty) {
        service.invoke('newMail', {'accountId': a.id, 'path': path, 'count': news.length});
      }
    } catch (_) {}
  });

  Future<void> reload() async {
    settings = await storage.loadSettings();
    final accounts = await storage.loadAccounts();
    await engine.apply(accounts);
    if (service is AndroidServiceInstance) {
      final n = engine.activeCount;
      await service.setForegroundNotificationInfo(
        title: 'EchoWP-Mail',
        content: n == 1 ? 'Push aktiv für 1 Ordner' : 'Push aktiv für $n Ordner',
      );
    }
    if (engine.activeCount == 0) {
      await service.stopSelf();
    }
  }

  service.on('reload').listen((_) => reload());
  service.on('stop').listen((_) async {
    await engine.stopAll();
    await service.stopSelf();
  });
  await reload();
}

/// Steuerung des Push-Dienstes aus der App heraus.
class PushService {
  static bool get supported => Platform.isAndroid;

  static Future<void> ensure({required bool anyPush}) async {
    if (!supported) return;
    try {
      final service = FlutterBackgroundService();
      if (!anyPush) {
        if (await service.isRunning()) service.invoke('stop');
        return;
      }
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            'E-Mail-Push',
            description: 'Dauerhafte Verbindung für sofortige Benachrichtigung',
            importance: Importance.low,
            showBadge: false,
          ));
      await service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: pushServiceMain,
          autoStart: true,
          autoStartOnBoot: true,
          isForegroundMode: true,
          notificationChannelId: _channelId,
          initialNotificationTitle: 'EchoWP-Mail',
          initialNotificationContent: 'Push wird verbunden …',
          foregroundServiceNotificationId: _serviceNotificationId,
          foregroundServiceTypes: [AndroidForegroundType.remoteMessaging],
        ),
        iosConfiguration: IosConfiguration(autoStart: false),
      );
      if (await service.isRunning()) {
        service.invoke('reload');
      } else {
        await service.startService();
      }
    } catch (_) {}
  }

  /// Meldungen des Dienstes an die App (neue Mails).
  static Stream<Map<String, dynamic>?> get newMail =>
      supported ? FlutterBackgroundService().on('newMail') : const Stream.empty();
}

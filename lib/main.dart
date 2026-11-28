import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'file_drop.dart';
import 'keyboard.dart';
import 'notifications.dart';
import 'screens/home_screen.dart';
import 'theme.dart';
import 'widgets/update_ticker.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  Intl.defaultLocale = 'de_DE';
  await Notifier.init();
  // Dateien per Drag & Drop (nur Windows-Fenster meldet sie)
  if (Platform.isWindows) FileDrop.init();
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const EchoMailApp()));
  // Esc / Alt+← = zurück (Tastatursteuerung, v. a. Windows)
  HardwareKeyboard.instance.addHandler((e) => handleKeyboardBack(e, state.routeObserver, state.navigatorKey));
  // Antippen einer Benachrichtigung / „Antworten“, während die App läuft
  Notifier.taps.listen(state.handleNotification);
  await state.load();
  // „Löschen“/„Als gelesen“ aus Benachrichtigungen: erledigt ein anderes Isolat (App lief im
  // Hintergrund), wird die Liste sofort angepasst; Liegengebliebenes wird jetzt nachgeholt.
  PendingActions.listen(state.notifyActionDone);
  state.processPendingActions();
  // App wurde über eine Benachrichtigung gestartet
  final launch = await Notifier.launchResponse();
  if (launch != null) await state.handleNotification(launch);
}

class EchoMailApp extends StatelessWidget {
  const EchoMailApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final mode = context.select<AppState, ThemeMode>((s) => s.settings.themeMode);
    return MaterialApp(
      title: 'EchoWP-Mail',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: state.messengerKey,
      navigatorKey: state.navigatorKey,
      navigatorObservers: [state.routeObserver],
      themeMode: mode,
      theme: echoTheme(Brightness.light),
      darkTheme: echoTheme(Brightness.dark),
      // Laufband bei verfügbarem Update – oben auf allen Bildschirmen
      builder: (context, child) => UpdateTickerFrame(child: child ?? const SizedBox.shrink()),
      home: const HomeScreen(),
    );
  }
}

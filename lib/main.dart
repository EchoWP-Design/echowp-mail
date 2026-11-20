import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'notifications.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  Intl.defaultLocale = 'de_DE';
  await Notifier.init();
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const EchoMailApp()));
  // Antippen einer Benachrichtigung / „Antworten“, während die App läuft
  Notifier.taps.listen(state.handleNotification);
  await state.load();
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
      themeMode: mode,
      theme: echoTheme(Brightness.light),
      darkTheme: echoTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'notifications.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE');
  Intl.defaultLocale = 'de_DE';
  await Notifier.init();
  final state = AppState();
  runApp(ChangeNotifierProvider.value(value: state, child: const EchoMailApp()));
  await state.load();
}

const seedColor = Color(0xFF0277BD);

class EchoMailApp extends StatelessWidget {
  const EchoMailApp({super.key});

  ThemeData _theme(Brightness b) {
    final base = ThemeData(
      colorSchemeSeed: seedColor,
      brightness: b,
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: b == Brightness.light ? seedColor : null,
        foregroundColor: b == Brightness.light ? Colors.white : null,
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 0.5),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final mode = context.select<AppState, ThemeMode>((s) => s.settings.themeMode);
    return MaterialApp(
      title: 'EchoWP-Mail',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: state.messengerKey,
      themeMode: mode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}

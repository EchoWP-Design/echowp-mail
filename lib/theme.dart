import 'package:flutter/material.dart';

/// EchoWP-Markenfarben (Corporate Design: Schwarz-Gelb).
const echoYellow = Color(0xFFFFD400);
const echoBlack = Color(0xFF0A0A0A);

/// Farbschema der App.
///
/// Grundlage ist ein neutrales Grau-Schema (keine farbstichigen Flächen),
/// darüber die Markenfarben:
/// - Hell: Akzente Schwarz, Kopfleisten Schwarz mit gelber Schrift
///   (gelber Text auf Weiß wäre kaum lesbar).
/// - Dunkel: Akzente Gelb auf Schwarz.
ColorScheme echoColorScheme(Brightness b) {
  final base = ColorScheme.fromSeed(
    seedColor: echoYellow,
    brightness: b,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
  );
  if (b == Brightness.dark) {
    return base.copyWith(
      primary: echoYellow,
      onPrimary: echoBlack,
      primaryContainer: const Color(0xFF4A3F00),
      onPrimaryContainer: const Color(0xFFFFE97A),
      secondary: echoYellow,
      onSecondary: echoBlack,
      secondaryContainer: const Color(0xFF3A3200),
      onSecondaryContainer: const Color(0xFFFFE97A),
      tertiary: const Color(0xFFFFE97A),
      onTertiary: echoBlack,
      surface: const Color(0xFF121212),
      onSurface: const Color(0xFFEDEDED),
    );
  }
  return base.copyWith(
    primary: echoBlack,
    onPrimary: echoYellow,
    primaryContainer: const Color(0xFFFFF1A6),
    onPrimaryContainer: echoBlack,
    secondary: const Color(0xFF6B5A00),
    onSecondary: Colors.white,
    secondaryContainer: const Color(0xFFFFE97A),
    onSecondaryContainer: echoBlack,
    tertiary: const Color(0xFF6B5A00),
    onTertiary: Colors.white,
    surface: Colors.white,
    onSurface: echoBlack,
  );
}

ThemeData echoTheme(Brightness b) {
  final cs = echoColorScheme(b);
  final base = ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
  );
  return base.copyWith(
    // Kopfleiste immer im Markenauftritt: Schwarz mit gelber Schrift.
    appBarTheme: const AppBarTheme(
      backgroundColor: echoBlack,
      foregroundColor: echoYellow,
      surfaceTintColor: Colors.transparent,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: echoYellow,
      foregroundColor: echoBlack,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: b == Brightness.dark ? echoYellow : echoBlack),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: b == Brightness.dark ? echoYellow : echoBlack,
      selectionColor: echoYellow.withValues(alpha: 0.45),
      selectionHandleColor: b == Brightness.dark ? echoYellow : echoBlack,
    ),
    dividerTheme: const DividerThemeData(space: 1, thickness: 0.5),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Zählt offene Vorschlagslisten o. Ä., die Esc selbst schließen (dann nicht zurückgehen).
class EscGuard {
  EscGuard._();
  static int open = 0;
}

/// Hält [EscGuard.open] hoch, solange das Kind angezeigt wird.
class EscGuarded extends StatefulWidget {
  final Widget child;
  const EscGuarded({super.key, required this.child});

  @override
  State<EscGuarded> createState() => _EscGuardedState();
}

class _EscGuardedState extends State<EscGuarded> {
  @override
  void initState() {
    super.initState();
    EscGuard.open++;
  }

  @override
  void dispose() {
    EscGuard.open--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Merkt sich die oberste Route (für die globale Zurück-Taste).
class TopRouteObserver extends NavigatorObserver {
  Route<dynamic>? top;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => top = route;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => top = previousRoute;
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => top = newRoute ?? top;
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (identical(route, top)) top = previousRoute;
  }
}

/// Esc bzw. Alt+← = zurück zur vorherigen Seite (Einstellungen, Mail, Schreiben …).
/// Dialoge, Menüs und Bottom-Sheets schließen sich mit Esc selbst und bleiben unberührt.
bool handleKeyboardBack(KeyEvent e, TopRouteObserver observer, GlobalKey<NavigatorState> nav) {
  if (e is! KeyDownEvent) return false;
  final k = e.logicalKey;
  final back = k == LogicalKeyboardKey.escape ||
      (HardwareKeyboard.instance.isAltPressed && k == LogicalKeyboardKey.arrowLeft);
  if (!back) return false;
  // Offene Vorschlagsliste: Esc schließt nur die Liste
  if (k == LogicalKeyboardKey.escape && EscGuard.open > 0) return false;
  final top = observer.top;
  if (top == null || top is PopupRoute || top.isFirst) return false;
  nav.currentState?.maybePop();
  return true;
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

/// EchoWP-Gelb und -Schwarz (wie das Laufband in EchoWP-Sim).
const _yellow = Color(0xFFFFD400);
const _black = Color(0xFF0A0A0A);

/// Legt bei einem verfügbaren Update ein Laufband (Schwarz auf Gelb) an den oberen Rand der App.
/// Antippen = „Jetzt updaten“, ✕ = „Später“ (für diese Version ausblenden).
///
/// Sitzt in `MaterialApp.builder` über dem Navigator → auf allen Bildschirmen sichtbar.
/// Deshalb hier keine Tooltips/Dialoge (dafür fehlt oberhalb des Navigators das Overlay).
class UpdateTickerFrame extends StatelessWidget {
  final Widget child;
  const UpdateTickerFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (!s.showUpdateBanner) return child;
    final r = s.update!;
    final progress = s.updateProgress;
    final String text;
    if (progress != null) {
      text = '⬇ Update ${r.label} wird geladen … ${(progress * 100).round()} %';
    } else if (s.updateError != null) {
      text = '⚠ ${s.updateError}  ·  Antippen für einen neuen Versuch';
    } else {
      text = '⬆ Update verfügbar: ${r.label}  ·  Antippen zum Installieren  ·  ✕ blendet den Hinweis bis zur '
          'nächsten Version aus';
    }
    final mq = MediaQuery.of(context);
    return Column(children: [
      Material(
        key: const ValueKey('update-ticker'),
        color: _yellow,
        child: Padding(
          padding: EdgeInsets.only(top: mq.padding.top, left: mq.padding.left, right: mq.padding.right),
          child: SizedBox(
            height: 30,
            child: Row(children: [
              Expanded(
                child: InkWell(
                  key: const ValueKey('update-ticker-tap'),
                  onTap: progress == null ? s.installUpdate : null,
                  child: progress == null
                      ? Marquee(text: text, style: _style)
                      : Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(text, style: _style, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                ),
              ),
              if (progress == null)
                Semantics(
                  button: true,
                  label: 'Später',
                  child: InkResponse(
                    key: const ValueKey('update-ticker-close'),
                    onTap: s.dismissUpdate,
                    radius: 18,
                    child: const SizedBox(width: 40, height: 30, child: Icon(Icons.close, size: 18, color: _black)),
                  ),
                ),
            ]),
          ),
        ),
      ),
      if (progress != null)
        LinearProgressIndicator(
          value: progress,
          minHeight: 3,
          color: _black,
          backgroundColor: _yellow.withValues(alpha: 0.5),
        ),
      // Die Statusleiste ist schon vom Laufband belegt → darunter keinen oberen Rand mehr
      Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: child)),
    ]);
  }

  static const _style = TextStyle(color: _black, fontWeight: FontWeight.w800, fontSize: 14);
}

/// Laufschrift von rechts nach links, endlos. Bei „Animationen reduzieren“ (Bedienungshilfen)
/// steht der Text still und wird gekürzt.
class Marquee extends StatefulWidget {
  final String text;
  final TextStyle style;
  /// Geschwindigkeit in logischen Pixeln pro Sekunde.
  final double speed;
  const Marquee({super.key, required this.text, required this.style, this.speed = 60});

  @override
  State<Marquee> createState() => _MarqueeState();
}

class _MarqueeState extends State<Marquee> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  double _distance = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _setup(double width, double textWidth) {
    final distance = width + textWidth;
    if (distance == _distance && _c.isAnimating) return;
    _distance = distance;
    _c.duration = Duration(milliseconds: (distance / widget.speed * 1000).round().clamp(1000, 600000));
    _c.repeat();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, box) {
        if (still || !box.maxWidth.isFinite) {
          _c.stop();
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(widget.text, style: widget.style, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          );
        }
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          textDirection: Directionality.of(context),
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final textWidth = tp.width;
        tp.dispose();
        final width = box.maxWidth;
        // Nach dem Aufbau starten (nicht während build den Controller umstellen)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _setup(width, textWidth);
        });
        return ClipRect(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, child) => Stack(children: [
              Positioned(
                left: width - _c.value * (width + textWidth),
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(widget.text, style: widget.style, maxLines: 1, softWrap: false),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

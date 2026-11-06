import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Whether endless background motion may run. Off by default, so anything that
/// waits for the app to settle still can; a phone's "remove animations"
/// setting switches it off too.
class Ambient extends InheritedWidget {
  const Ambient({super.key, required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<Ambient>();
    return (scope?.enabled ?? false) && !MediaQuery.disableAnimationsOf(context);
  }

  @override
  bool updateShouldNotify(Ambient oldWidget) => enabled != oldWidget.enabled;
}

/// Slow light drifting behind the whole app.
class Aurora extends StatefulWidget {
  const Aurora({super.key, required this.background, required this.color});

  final Color background;
  final Color color;

  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  // The light moves slowly, so 12 repaints a second look the same as 60 and
  // leave the phone's battery alone.
  static const _stepsPerSecond = 12;

  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);

  void _tick(Duration elapsed) {
    final step = elapsed.inMilliseconds * _stepsPerSecond ~/ 1000;
    _time.value = step / _stepsPerSecond;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = Ambient.of(context);
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _AuroraPainter(_time, widget.background, widget.color),
          size: Size.infinite,
        ),
      );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.time, this.background, this.color) : super(repaint: time);

  final ValueNotifier<double> time;
  final Color background;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final t = time.value;
    final hsl = HSLColor.fromColor(color);
    final blobs = [
      (0.15, 0.12, 0.95, 0.20, color),
      (0.92, 0.34, 0.80, 0.14, hsl.withHue((hsl.hue + 42) % 360).toColor()),
      (0.30, 0.82, 1.05, 0.11, hsl.withHue((hsl.hue + 320) % 360).toColor()),
    ];
    for (final (i, (x, y, radius, alpha, tint)) in blobs.indexed) {
      final center = Offset(
        size.width * (x + 0.10 * math.sin(t * 0.13 + i * 2.1)),
        size.height * (y + 0.06 * math.cos(t * 0.11 + i * 1.3)),
      );
      final r = size.width * radius;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [tint.withValues(alpha: alpha), tint.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.background != background || old.color != color;
}

/// Lifts its child into place when it first appears.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.index, required this.child});

  /// Later items start a little later, so a page arrives as a cascade.
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + index * 70),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        final start = index * 70 / (420 + index * 70);
        final shown = ((value - start) / (1 - start)).clamp(0.0, 1.0);
        return Opacity(
          opacity: shown,
          child: Transform.translate(offset: Offset(0, 18 * (1 - shown)), child: child),
        );
      },
    );
  }
}

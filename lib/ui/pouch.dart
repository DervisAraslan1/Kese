import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'ambient.dart';
import 'theme.dart';

/// How full the pouch is: the share of this month's income still left.
double pouchLevel({required int spent, required int earned}) {
  if (earned <= 0) return 0;
  return ((earned - spent) / earned).clamp(0.0, 1.0);
}

const _warning = Color(0xFFF5A524);

/// The liquid stays calm until a third is left, then heats up toward danger.
Color pouchColor(double level, Color accent, Color danger) {
  if (level >= 0.5) return accent;
  if (level >= 0.2) return Color.lerp(_warning, accent, (level - 0.2) / 0.3)!;
  return Color.lerp(danger, _warning, level / 0.2)!;
}

/// Even an empty pouch shows a little at the bottom, or it reads as a bug.
const _minVisibleLevel = 0.05;
const _liquidTop = 0.30;
const _textTop = 0.42;
const _textHeight = 0.36;

double _liquidY(double level, double height) {
  final shown = _minVisibleLevel + level * (1 - _minVisibleLevel);
  return height * (1 - shown * (1 - _liquidTop));
}

/// A pouch of liquid that follows the money: level for what is left, color for
/// how tight it is, a coin and a splash when the amount changes.
class LivePouch extends StatefulWidget {
  const LivePouch({
    super.key,
    required this.level,
    required this.amount,
    required this.child,
    this.height = 300,
  });

  final double level;

  /// Watched only to see money move in or out.
  final int amount;

  /// Sits across the pouch and changes color where the liquid reaches it.
  final Widget child;
  final double height;

  @override
  State<LivePouch> createState() => _LivePouchState();
}

class _LivePouchState extends State<LivePouch> with TickerProviderStateMixin {
  late final Ticker _ticker = createTicker(
    (elapsed) => _time.value = elapsed.inMicroseconds / 1000000,
  );
  final _time = ValueNotifier<double>(0);
  late final AnimationController _level = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final AnimationController _splash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  );
  late final AnimationController _coin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  bool _coinIn = false;

  @override
  void initState() {
    super.initState();
    _level.animateTo(widget.level, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = Ambient.of(context);
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
  }

  @override
  void didUpdateWidget(LivePouch old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) {
      _level.animateTo(widget.level, curve: Curves.easeOutCubic);
    }
    if (old.amount != widget.amount) {
      _coinIn = widget.amount > old.amount;
      _coin.forward(from: 0);
      _shake();
    }
  }

  void _shake() {
    _splash.value = 1;
    _splash.animateTo(0, curve: Curves.easeOut);
  }

  void _touch() {
    HapticFeedback.selectionClick();
    _shake();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _level.dispose();
    _splash.dispose();
    _coin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final danger = context.keseColors.danger;
    final motion = Listenable.merge([_time, _level, _splash, _coin]);
    final height = widget.height;
    final width = height * 0.92;
    final textTop = height * _textTop;
    final textHeight = height * _textHeight;

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _touch,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PouchPainter(
                      repaint: motion,
                      time: _time,
                      level: _level,
                      splash: _splash,
                      coin: _coin,
                      coinIn: () => _coinIn,
                      target: widget.level,
                      accent: colors.primary,
                      danger: danger,
                      ink: colors.onSurface,
                      body: colors.surfaceContainerHighest,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: width * 0.11,
                right: width * 0.11,
                top: textTop,
                height: textHeight,
                child: AnimatedBuilder(
                  animation: _level,
                  child: Center(child: widget.child),
                  builder: (context, child) {
                    final liquid = pouchColor(widget.level, colors.primary, danger);
                    final edge =
                        ((_liquidY(_level.value, height) - textTop) / textHeight).clamp(0.0, 1.0);
                    return ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [0, edge, edge, 1],
                        colors: [
                          colors.onSurface,
                          colors.onSurface,
                          readableOn(liquid),
                          readableOn(liquid),
                        ],
                      ).createShader(bounds),
                      child: child,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PouchPainter extends CustomPainter {
  _PouchPainter({
    required Listenable repaint,
    required this.time,
    required this.level,
    required this.splash,
    required this.coin,
    required this.coinIn,
    required this.target,
    required this.accent,
    required this.danger,
    required this.ink,
    required this.body,
  }) : super(repaint: repaint);

  final ValueNotifier<double> time;
  final Animation<double> level;
  final Animation<double> splash;
  final Animation<double> coin;
  final bool Function() coinIn;
  final double target;
  final Color accent;
  final Color danger;
  final Color ink;
  final Color body;

  Path _bag(Size s) => Path()
    ..moveTo(s.width * .38, s.height * .20)
    ..cubicTo(s.width * .22, s.height * .30, s.width * .03, s.height * .46, s.width * .03, s.height * .68)
    ..cubicTo(s.width * .03, s.height * .90, s.width * .20, s.height, s.width * .50, s.height)
    ..cubicTo(s.width * .80, s.height, s.width * .97, s.height * .90, s.width * .97, s.height * .68)
    ..cubicTo(s.width * .97, s.height * .46, s.width * .78, s.height * .30, s.width * .62, s.height * .20)
    ..close();

  Path _ruffle(Size s) => Path()
    ..moveTo(s.width * .38, s.height * .20)
    ..cubicTo(s.width * .30, s.height * .12, s.width * .25, s.height * .05, s.width * .29, s.height * .02)
    ..quadraticBezierTo(s.width * .40, s.height * .075, s.width * .50, s.height * .03)
    ..quadraticBezierTo(s.width * .60, s.height * .075, s.width * .71, s.height * .02)
    ..cubicTo(s.width * .75, s.height * .05, s.width * .70, s.height * .12, s.width * .62, s.height * .20)
    ..close();

  Path _wave(Size s, double y, double amp, double phase, double stretch) {
    final path = Path()..moveTo(0, s.height);
    for (var x = 0.0; x <= s.width + 6; x += 6) {
      final u = x / s.width * math.pi * 2;
      path.lineTo(
        x,
        y + math.sin(u * stretch + phase) * amp + math.sin(u * stretch * 2.3 - phase * 1.4) * amp * .4,
      );
    }
    return path
      ..lineTo(s.width, s.height)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final jolt = splash.value;
    // A shake also moves the waves, so it still shows with ambient motion off.
    final t = time.value + (1 - jolt) * 2.2;
    final y = _liquidY(level.value, size.height);
    final liquid = pouchColor(target, accent, danger);
    final deep = Color.lerp(liquid, Colors.black, .38)!;
    final amp = size.height * (.009 + jolt * .04);

    final center = Offset(size.width / 2, size.height * .66);
    final glowRadius = size.width * (.82 + jolt * .1);
    canvas.drawCircle(
      center,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [liquid.withValues(alpha: .34 + jolt * .18), liquid.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: glowRadius)),
    );

    final bag = _bag(size);
    final ruffle = _ruffle(size);
    final bagRect = Offset.zero & size;

    canvas.drawPath(ruffle, Paint()..color = body);
    canvas.drawPath(
      bag,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [body.withValues(alpha: .92), body.withValues(alpha: .55)],
        ).createShader(bagRect),
    );

    canvas.save();
    canvas.clipPath(bag);
    canvas.drawPath(
      _wave(size, y - amp * .7, amp * 1.1, -t * 1.05 + 1.7, 1.15),
      Paint()..color = deep.withValues(alpha: .75),
    );
    canvas.drawPath(
      _wave(size, y, amp, t * 1.35, 1),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(liquid, Colors.white, .22)!, liquid, deep],
          stops: const [0, .25, 1],
        ).createShader(Rect.fromLTRB(0, y - amp, size.width, size.height)),
    );

    final bubble = Paint()..color = Colors.white.withValues(alpha: .28);
    for (var i = 0; i < 9; i++) {
      final seed = i * 12.9898;
      final x = size.width * (.14 + .72 * (math.sin(seed) * .5 + .5));
      final speed = .05 + .04 * (i % 3);
      final rise = (t * speed + i * .137) % 1;
      final by = size.height - (size.height - y) * rise;
      final fade = math.sin(rise * math.pi);
      if (by < size.height * .99 && by > y) {
        canvas.drawCircle(
          Offset(x + math.sin(t + i) * 5, by),
          (1.5 + (i % 3)) * fade,
          bubble,
        );
      }
    }
    canvas.restore();

    canvas.drawPath(
      bag,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = ink.withValues(alpha: .26),
    );
    canvas.drawPath(
      ruffle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = ink.withValues(alpha: .26),
    );

    final gloss = Path()
      ..moveTo(size.width * .13, size.height * .74)
      ..cubicTo(size.width * .11, size.height * .58, size.width * .20, size.height * .44, size.width * .31, size.height * .34);
    canvas.drawPath(
      gloss,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5
        ..color = Colors.white.withValues(alpha: .13),
    );

    final tie = RRect.fromRectAndRadius(
      Rect.fromLTRB(size.width * .345, size.height * .175, size.width * .655, size.height * .225),
      Radius.circular(size.height * .025),
    );
    canvas.drawRRect(tie, Paint()..color = liquid);
    canvas.drawCircle(
      Offset(size.width * .655, size.height * .20),
      size.height * .022,
      Paint()..color = Color.lerp(liquid, Colors.white, .3)!,
    );

    if (coin.isAnimating) {
      final p = Curves.easeIn.transform(coin.value);
      final top = size.height * .08;
      // Income drops in; spending flies out of the pouch.
      final cy = coinIn() ? top + (y - top) * p : y + (-size.height * .12 - y) * p;
      final cx = size.width * .5 + math.sin(p * 9) * 10;
      final r = size.height * .03;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = _warning.withValues(alpha: 1 - p * (coinIn() ? 0 : .8)),
      );
      canvas.drawCircle(
        Offset(cx, cy),
        r * .62,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: .55 * (1 - p * .6)),
      );
    }
  }

  @override
  bool shouldRepaint(_PouchPainter old) =>
      old.target != target ||
      old.accent != accent ||
      old.danger != danger ||
      old.ink != ink ||
      old.body != body;
}

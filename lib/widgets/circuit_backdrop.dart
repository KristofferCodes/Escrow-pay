import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// The near-black ground with a faint circuit trace behind key screens.
///
/// Drawn rather than shipped as an asset so it scales to any screen without a
/// second file, and so the trace density can be tuned in one place. It sits
/// under a radial accent wash that keeps the top of the screen from reading as
/// a flat rectangle.
class CircuitBackdrop extends StatelessWidget {
  const CircuitBackdrop({
    required this.child,
    this.glowAlignment = const Alignment(0, -0.75),
    this.glowColor = Palette.violet,
    super.key,
  });

  final Widget child;
  final Alignment glowAlignment;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Palette.void_),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Accent wash. Large and very low opacity — it should register as
          // depth, not as a colour.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: glowAlignment,
                radius: 1.1,
                colors: [glowColor.withValues(alpha: 0.20), Colors.transparent],
              ),
            ),
          ),
          const RepaintBoundary(
            child: CustomPaint(painter: _CircuitPainter(), size: Size.infinite),
          ),
          child,
        ],
      ),
    );
  }
}

class _CircuitPainter extends CustomPainter {
  const _CircuitPainter();

  static const _cell = 34.0;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.028)
      ..strokeWidth = 1;

    for (var x = 0.0; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // A handful of traces that break the grid's regularity. The seed is fixed
    // so the pattern does not reshuffle on every repaint.
    final random = math.Random(7);
    final trace = Paint()
      ..color = Palette.cyan.withValues(alpha: 0.10)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final node = Paint()..color = Palette.cyan.withValues(alpha: 0.22);

    final columns = (size.width / _cell).floor();
    final rows = (size.height / _cell).floor();
    if (columns < 4 || rows < 4) return;

    for (var i = 0; i < 14; i++) {
      var x = random.nextInt(columns) * _cell;
      var y = random.nextInt(rows) * _cell;
      final path = Path()..moveTo(x, y);

      // Circuit traces only turn at right angles.
      final segments = 2 + random.nextInt(3);
      for (var s = 0; s < segments; s++) {
        final length = (1 + random.nextInt(3)) * _cell;
        if (s.isEven) {
          x = (x + (random.nextBool() ? length : -length)).clamp(
            0.0,
            size.width,
          );
        } else {
          y = (y + (random.nextBool() ? length : -length)).clamp(
            0.0,
            size.height,
          );
        }
        path.lineTo(x, y);
      }

      canvas.drawPath(path, trace);
      canvas.drawCircle(Offset(x, y), 2.0, node);
    }
  }

  @override
  bool shouldRepaint(_CircuitPainter oldDelegate) => false;
}

import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// The Escrow Pay monogram: an E whose middle arm floats free of the spine.
///
/// The same geometry as the launcher icon, drawn rather than loaded from a
/// PNG so it stays sharp at any size and needs no asset. Proportions are
/// authored on the 1024 grid used by `scripts/generate_icons.py`; change one
/// and the other should follow, or the app and its icon stop matching.
class EscrowMark extends StatelessWidget {
  const EscrowMark({this.size = 30, this.gradient, super.key});

  final double size;

  /// Defaults to the accent ramp. Pass a solid-colour gradient to flatten it
  /// where a gradient would compete.
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter(gradient ?? Palette.accent)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter(this.gradient);

  final Gradient gradient;

  // The mark's own bounds inside the 1024 icon grid.
  static const _gridX = 320.0;
  static const _gridY = 300.0;
  static const _gridW = 384.0;
  static const _gridH = 424.0;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / _gridW;
    final sy = size.height / _gridH;

    // Every stroke is 76 units wide with fully rounded ends, so the arms read
    // as one family rather than a spine with decoration.
    RRect bar(double cx, double cy, double hw, double hh) {
      final rect = Rect.fromLTRB(
        (cx - hw - _gridX) * sx,
        (cy - hh - _gridY) * sy,
        (cx + hw - _gridX) * sx,
        (cy + hh - _gridY) * sy,
      );
      return RRect.fromRectAndRadius(
        rect,
        Radius.circular(38 * (sx < sy ? sx : sy)),
      );
    }

    final paint = Paint()
      ..shader = gradient.createShader(Offset.zero & size)
      ..isAntiAlias = true;

    canvas
      ..drawRRect(bar(358, 512, 38, 212), paint) // spine
      ..drawRRect(bar(512, 338, 192, 38), paint) // top arm
      // Detached: value held between two parties, touched by neither.
      ..drawRRect(bar(550, 512, 90, 38), paint)
      ..drawRRect(bar(512, 686, 192, 38), paint); // bottom arm
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.gradient != gradient;
}

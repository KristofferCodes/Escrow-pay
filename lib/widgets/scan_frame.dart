import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// The viewfinder overlay on the camera screen.
///
/// A static square reads as a dead app while the camera hunts for focus, so
/// the frame stays alive: a line sweeps the aperture, and the corner brackets
/// snap to the accent colour the moment a valid offer is decoded.
class ScanFrame extends StatefulWidget {
  const ScanFrame({this.locked = false, this.size = 260, super.key});

  /// True once a valid escrow offer has been decoded from the camera feed.
  final bool locked;
  final double size;

  @override
  State<ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<ScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void didUpdateWidget(ScanFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Stop sweeping once there is nothing left to look for.
    if (widget.locked && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.locked && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _ScanFramePainter(
              sweep: _controller.value,
              locked: widget.locked,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter({required this.sweep, required this.locked});

  final double sweep;
  final bool locked;

  static const _corner = 34.0;
  static const _radius = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    final colour = locked ? Palette.success : Palette.cyan;
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(_radius));

    // Dim everything outside the aperture so the eye goes to the frame.
    canvas
      ..saveLayer(rect.inflate(2000), Paint())
      ..drawRect(
        rect.inflate(2000),
        Paint()..color = Colors.black.withValues(alpha: 0.55),
      )
      ..drawRRect(rrect, Paint()..blendMode = BlendMode.clear)
      ..restore();

    // Faint full outline, then bright corner brackets over it.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.18),
    );

    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..color = colour;

    final path = Path()
      // Top-left.
      ..moveTo(0, _corner)
      ..lineTo(0, _radius)
      ..quadraticBezierTo(0, 0, _radius, 0)
      ..lineTo(_corner, 0)
      // Top-right.
      ..moveTo(size.width - _corner, 0)
      ..lineTo(size.width - _radius, 0)
      ..quadraticBezierTo(size.width, 0, size.width, _radius)
      ..lineTo(size.width, _corner)
      // Bottom-right.
      ..moveTo(size.width, size.height - _corner)
      ..lineTo(size.width, size.height - _radius)
      ..quadraticBezierTo(
        size.width,
        size.height,
        size.width - _radius,
        size.height,
      )
      ..lineTo(size.width - _corner, size.height)
      // Bottom-left.
      ..moveTo(_corner, size.height)
      ..lineTo(_radius, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - _radius)
      ..lineTo(0, size.height - _corner);

    canvas
      ..drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..color = colour.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      )
      ..drawPath(path, bracket);

    if (locked) return;

    // Sweep line. Bounces rather than wrapping, so it never jumps.
    final travel = 1 - (sweep * 2 - 1).abs();
    final y = 14 + travel * (size.height - 28);

    canvas.drawRect(
      Rect.fromLTWH(10, y - 1, size.width - 20, 2),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            colour.withValues(alpha: 0.95),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(10, y - 1, size.width - 20, 2))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }

  @override
  bool shouldRepaint(_ScanFramePainter old) =>
      old.sweep != sweep || old.locked != locked;
}

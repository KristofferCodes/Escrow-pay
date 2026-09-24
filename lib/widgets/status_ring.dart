import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/escrow.dart';
import '../theme/palette.dart';

/// The escrow status ring: the one element on screen that answers "where is my
/// money right now".
///
/// Three things animate independently, which is what stops it reading as a
/// plain progress indicator:
///  - the arc sweeps between states on a spring, so a state change is felt
///    rather than just observed;
///  - a glow breathes continuously while funds are in flight, and settles to a
///    steady ring once the escrow is closed;
///  - a comet rides the arc's leading edge while the outcome is still open.
class StatusRing extends StatefulWidget {
  const StatusRing({
    required this.state,
    required this.child,
    this.size = 232,
    this.pending = false,
    super.key,
  });

  final EscrowState state;

  /// Amount and label live inside the ring.
  final Widget child;
  final double size;

  /// Set while a transaction is in flight but the chain has not confirmed it.
  final bool pending;

  @override
  State<StatusRing> createState() => _StatusRingState();
}

class _StatusRingState extends State<StatusRing> with TickerProviderStateMixin {
  /// Free-running; drives the breathing glow and the comet.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  /// Driven on state change only.
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
    value: 1,
  );

  late double _from = _progressFor(widget.state);
  late double _to = _progressFor(widget.state);
  late Color _fromColor = Palette.forState(widget.state.key);
  late Color _toColor = _fromColor;

  static double _progressFor(EscrowState state) => switch (state) {
    EscrowState.created => 0.28,
    EscrowState.funded => 0.64,
    EscrowState.released || EscrowState.refunded => 1.0,
  };

  @override
  void didUpdateWidget(StatusRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state == widget.state) return;

    // Hand off from wherever the arc actually is, so a state change landing
    // mid-sweep does not snap backwards.
    _from = _currentProgress;
    _fromColor = _currentColor;
    _to = _progressFor(widget.state);
    _toColor = Palette.forState(widget.state.key);
    _sweep.forward(from: 0);
  }

  double get _currentProgress {
    final t = Curves.easeOutBack.transform(_sweep.value).clamp(0.0, 1.0);
    return _from + (_to - _from) * t;
  }

  Color get _currentColor =>
      Color.lerp(_fromColor, _toColor, _sweep.value) ?? _toColor;

  @override
  void dispose() {
    _pulse.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pulse, _sweep]),
          builder: (context, child) => CustomPaint(
            painter: _RingPainter(
              progress: _currentProgress,
              color: _currentColor,
              pulse: _pulse.value,
              // A settled escrow stops asking for attention.
              animate: widget.pending || !widget.state.isSettled,
            ),
            child: Center(child: child),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.pulse,
    required this.animate,
  });

  final double progress;
  final Color color;
  final double pulse;
  final bool animate;

  static const _stroke = 10.0;
  static const _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = (size.shortestSide - _stroke) / 2 - 12;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    // A triangle wave, so the glow eases in and out symmetrically instead of
    // snapping back at the end of each cycle.
    final breath = animate ? (1 - (pulse * 2 - 1).abs()) : 0.45;

    // Outer glow.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke + 10 + breath * 8
        ..color = color.withValues(alpha: 0.05 + breath * 0.13)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 + breath * 10),
    );

    // Unfilled track.
    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = Colors.white.withValues(alpha: 0.06),
    );

    // Progress arc. The sweep gradient is rotated to the arc's start so the
    // colour ramp always runs along the arc, not across the canvas.
    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      rect,
      _startAngle,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: 2 * math.pi,
          colors: [color.withValues(alpha: 0.55), color, Palette.cyan, color],
          transform: const GradientRotation(_startAngle),
        ).createShader(rect),
    );

    if (!animate) return;

    // Comet at the leading edge, riding a little ahead of the arc.
    final headAngle = _startAngle + sweepAngle;
    final head =
        centre + Offset(math.cos(headAngle), math.sin(headAngle)) * radius;

    canvas
      ..drawCircle(
        head,
        6 + breath * 3,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.30 + breath * 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      )
      ..drawCircle(head, 3.6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.pulse != pulse ||
      old.animate != animate;
}

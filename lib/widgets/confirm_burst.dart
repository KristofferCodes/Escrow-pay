import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/palette.dart';

/// The one-shot particle burst played when a transaction confirms.
///
/// Deliberately restrained: two dozen particles, under a second, no gravity,
/// no trails. It should read as the moment landing, not as a celebration
/// screen — the ring settling into its final colour is the real payload.
class ConfirmBurst extends StatefulWidget {
  const ConfirmBurst({
    required this.child,
    required this.trigger,
    this.color = Palette.cyan,
    super.key,
  });

  final Widget child;

  /// Play the burst whenever this value changes to a new non-null value.
  /// Using a token rather than a bool keeps repeat confirmations replayable
  /// without the caller having to reset a flag.
  final Object? trigger;
  final Color color;

  @override
  State<ConfirmBurst> createState() => _ConfirmBurstState();
}

class _ConfirmBurstState extends State<ConfirmBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  late final List<_Particle> _particles = _seed();

  static List<_Particle> _seed() {
    final random = math.Random();
    return List.generate(26, (i) {
      // Spread evenly around the circle, then jitter, so there are no gaps
      // and no clumps.
      final base = (i / 26) * 2 * math.pi;
      return _Particle(
        angle: base + (random.nextDouble() - 0.5) * 0.35,
        distance: 64 + random.nextDouble() * 76,
        size: 1.8 + random.nextDouble() * 2.6,
        delay: random.nextDouble() * 0.16,
      );
    });
  }

  @override
  void didUpdateWidget(ConfirmBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != null && widget.trigger != oldWidget.trigger) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => _controller.isDismissed
                    ? const SizedBox.shrink()
                    : CustomPaint(
                        painter: _BurstPainter(
                          progress: _controller.value,
                          particles: _particles,
                          color: widget.color,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Particle {
  const _Particle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.delay,
  });

  final double angle;
  final double distance;
  final double size;
  final double delay;
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter({
    required this.progress,
    required this.particles,
    required this.color,
  });

  final double progress;
  final List<_Particle> particles;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);

    for (final particle in particles) {
      // Each particle runs its own 0..1 over the remaining time after its
      // delay, so staggered starts still finish together.
      final span = 1 - particle.delay;
      final local = ((progress - particle.delay) / span).clamp(0.0, 1.0);
      if (local <= 0) continue;

      final travel = Curves.easeOutCubic.transform(local);
      final fade = 1 - Curves.easeInCubic.transform(local);

      final offset =
          centre +
          Offset(math.cos(particle.angle), math.sin(particle.angle)) *
              particle.distance *
              travel;

      canvas.drawCircle(
        offset,
        particle.size * (1 - travel * 0.45),
        Paint()
          ..color = Color.lerp(
            Colors.white,
            color,
            travel,
          )!.withValues(alpha: fade * 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}

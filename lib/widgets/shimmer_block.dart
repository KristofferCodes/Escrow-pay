import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';

/// A shimmering placeholder, used instead of a spinner while the chain is
/// being read.
///
/// The point is that the user sees the shape of the answer before the answer
/// arrives, so confirmation lands as content filling in rather than a layout
/// jump.
class ShimmerBlock extends StatefulWidget {
  const ShimmerBlock({
    this.width,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    super.key,
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  State<ShimmerBlock> createState() => _ShimmerBlockState();
}

class _ShimmerBlockState extends State<ShimmerBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Travel from fully off one edge to fully off the other so the
          // highlight never appears to be parked.
          final shift = _controller.value * 3 - 1.5;
          return Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              gradient: LinearGradient(
                begin: Alignment(shift - 1, 0),
                end: Alignment(shift + 1, 0),
                colors: const [
                  Color(0x0DFFFFFF),
                  Color(0x26FFFFFF),
                  Color(0x0DFFFFFF),
                ],
                stops: const [0.2, 0.5, 0.8],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The skeleton shown while an escrow is first read from the cluster. It
/// mirrors the real panel's layout so nothing shifts when data lands.
class EscrowSkeleton extends StatelessWidget {
  const EscrowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: ShimmerBlock(
            width: 232,
            height: 232,
            borderRadius: BorderRadius.all(Radius.circular(116)),
          ),
        ),
        Gap.xl,
        const ShimmerBlock(width: 160, height: 22),
        Gap.md,
        const ShimmerBlock(height: 14),
        Gap.sm,
        const ShimmerBlock(width: 220, height: 14),
        Gap.lg,
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: Radii.panel,
            border: Border.all(color: Palette.hairline),
          ),
          child: const Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              children: [
                ShimmerBlock(height: 14),
                SizedBox(height: 14),
                ShimmerBlock(height: 14),
                SizedBox(height: 14),
                ShimmerBlock(height: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

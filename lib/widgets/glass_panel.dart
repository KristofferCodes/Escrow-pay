import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';

/// A translucent, blurred panel.
///
/// The blur is the expensive part, so each panel is wrapped in a
/// [RepaintBoundary] — without one, an animating sibling forces every panel on
/// screen to re-blur each frame.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.borderRadius = Radii.panel,
    this.accent,
    this.blur = 18,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// Tints the border and adds an outer glow. Used to carry escrow state.
  final Color? accent;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final edge = accent ?? Palette.hairlineStrong;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            if (accent != null)
              BoxShadow(
                color: accent!.withValues(alpha: 0.22),
                blurRadius: 32,
                spreadRadius: -6,
              )
            else
              const BoxShadow(
                color: Color(0x66000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                gradient: Palette.glass,
                borderRadius: borderRadius,
                border: Border.all(
                  color: accent == null ? edge : edge.withValues(alpha: 0.45),
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A label/value row for transaction details. Values default to mono so
/// addresses and amounts line up down the panel.
class DetailRow extends StatelessWidget {
  const DetailRow({
    required this.label,
    required this.value,
    this.valueStyle,
    this.trailing,
    super.key,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: valueStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[Gap.sm, trailing!],
        ],
      ),
    );
  }
}

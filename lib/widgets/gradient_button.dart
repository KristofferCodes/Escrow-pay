import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/palette.dart';

/// The primary call to action.
///
/// It owns three states the demo leans on: idle, pressed (scale + glow damp),
/// and busy, where the label is swapped for a progress indicator so the user
/// can see the wallet round trip is underway rather than wondering if the tap
/// landed.
class GradientButton extends StatefulWidget {
  const GradientButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.gradient = Palette.accent,
    super.key,
  });

  final String label;
  final IconData? icon;

  /// `null` disables the button.
  final VoidCallback? onPressed;
  final bool busy;
  final Gradient gradient;

  bool get _enabled => onPressed != null && !busy;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget._enabled;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: enabled ? 1 : 0.45,
            duration: const Duration(milliseconds: 180),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: widget.gradient,
                borderRadius: Radii.control,
                boxShadow: [
                  if (enabled && !_pressed)
                    BoxShadow(
                      color: Palette.violet.withValues(alpha: 0.38),
                      blurRadius: 26,
                      spreadRadius: -6,
                      offset: const Offset(0, 8),
                    ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: widget.busy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Row(
                        key: const ValueKey('label'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, size: 19, color: Colors.white),
                            Gap.sm,
                          ],
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quieter sibling: same geometry, no fill. For destructive or secondary
/// paths such as refund, which should never out-shout confirm.
class OutlineButton extends StatelessWidget {
  const OutlineButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.color = Palette.textSecondary,
    super.key,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: OutlinedButton.icon(
        onPressed: enabled ? onPressed : null,
        icon: busy
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              )
            : Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: color.withValues(alpha: 0.35)),
          shape: const RoundedRectangleBorder(borderRadius: Radii.control),
        ),
      ),
    );
  }
}

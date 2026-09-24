import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/money.dart';
import '../theme/app_theme.dart';
import '../theme/palette.dart';
import '../theme/typography.dart';

/// A truncated wallet address that can be copied.
///
/// Addresses are shown in mono with both ends visible so they can be checked
/// against a wallet screen; tapping copies the full value, because a truncated
/// address is useless for anything but recognition.
class AddressChip extends StatefulWidget {
  const AddressChip({
    required this.address,
    this.label,
    this.accent = Palette.textSecondary,
    super.key,
  });

  final String address;
  final String? label;
  final Color accent;

  @override
  State<AddressChip> createState() => _AddressChipState();
}

class _AddressChipState extends State<AddressChip> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.address));
    await HapticFeedback.selectionClick();
    if (!mounted) return;

    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${widget.label ?? 'Address'} ${widget.address}, tap to copy',
      child: InkWell(
        onTap: _copy,
        borderRadius: Radii.chip,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: Radii.chip,
            color: Palette.surfaceRaised,
            border: Border.all(color: Palette.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.label != null) ...[
                Text(
                  widget.label!,
                  style: AppType.mono(size: 11, color: Palette.textMuted),
                ),
                Gap.sm,
              ],
              Text(
                Money.shortAddress(widget.address),
                style: AppType.mono(size: 12.5, color: widget.accent),
              ),
              Gap.sm,
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _copied ? Icons.check_rounded : Icons.copy_rounded,
                  key: ValueKey(_copied),
                  size: 13,
                  color: _copied ? Palette.success : Palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pill carrying the escrow's current state.
class StatePill extends StatelessWidget {
  const StatePill({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: Radii.chip,
        color: color.withValues(alpha: 0.13),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          Gap.sm,
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

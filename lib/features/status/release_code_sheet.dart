import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/money.dart';
import '../../core/release_code.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';

/// The buyer's handover QR.
///
/// Showing this is the payment. There is no second step and no undo, so the
/// screen says so plainly rather than treating it as just another QR.
class ReleaseCodeSheet extends StatelessWidget {
  const ReleaseCodeSheet({
    required this.payload,
    required this.amount,
    required this.seller,
    super.key,
  });

  final ReleasePayload payload;
  final int amount;
  final String seller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Palette.hairlineStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Gap.lg,
            Text('Show this to the seller', style: text.titleLarge),
            Gap.sm,
            Text(
              'Scanning it pays ${Money.sol(amount)} to '
              '${Money.shortAddress(seller, edge: 5)}. This cannot be undone.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            Gap.lg,

            // White ground is a scanner requirement, not a style choice.
            Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: Radii.panel,
                    boxShadow: [
                      BoxShadow(
                        color: Palette.success.withValues(alpha: 0.30),
                        blurRadius: 44,
                        spreadRadius: -10,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: payload.encode(),
                    version: QrVersions.auto,
                    size: 232,
                    backgroundColor: Colors.white,
                    // High correction: a phone camera reading another phone's
                    // screen deals with glare and moire.
                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Palette.void_,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Palette.void_,
                    ),
                  ),
                )
                .animate()
                .fadeIn(duration: 300.ms)
                .scaleXY(begin: 0.95, curve: Curves.easeOutBack),

            Gap.lg,
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Palette.textMuted,
                ),
                Gap.sm,
                Expanded(
                  child: Text(
                    'The code only ever pays the seller named above — it '
                    'cannot be pointed anywhere else, so it is safe to show.',
                    style: text.bodyMedium,
                  ),
                ),
              ],
            ),
            Gap.md,
            _CopyLink(payload: payload),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Hide'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Escape hatch for when scanning will not cooperate — bad light, a cracked
/// screen, a camera that will not focus — and the way to drive a handover
/// when only one phone is in the room.
///
/// This does put a payment-authorising secret on the clipboard, which other
/// apps can read on older Android. The exposure is narrow because the sheet
/// only appears after the buyer has confirmed they inspected the item and
/// are happy to pay: at that point an early release costs them the refund
/// option they were about to give up anyway. Worth the trade for a path that
/// still works when the camera does not.
class _CopyLink extends StatefulWidget {
  const _CopyLink({required this.payload});

  final ReleasePayload payload;

  @override
  State<_CopyLink> createState() => _CopyLinkState();
}

class _CopyLinkState extends State<_CopyLink> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.payload.encode()));
    await HapticFeedback.selectionClick();
    if (!mounted) return;

    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _copy,
      icon: Icon(
        _copied ? Icons.check_rounded : Icons.copy_rounded,
        size: 16,
        color: _copied ? Palette.success : Palette.textSecondary,
      ),
      label: Text(
        _copied ? 'Copied' : "Copy link (if scanning won't work)",
        style: TextStyle(
          color: _copied ? Palette.success : Palette.textSecondary,
        ),
      ),
    );
  }
}

/// Asked before the code is ever on screen.
///
/// The whole value of the code is that it is shown *after* inspection; a
/// buyer who flashes it on arrival has given up the protection they funded.
Future<bool> confirmInspected(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Palette.surfaceRaised,
      shape: const RoundedRectangleBorder(borderRadius: Radii.panel),
      title: const Text('Happy with the item?'),
      content: const Text(
        'Only show this code once you have inspected the item and are happy '
        'with it. Scanning it pays the seller immediately, and you will not '
        'be able to refund afterwards.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not yet'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(
            'Show the code',
            style: TextStyle(color: Palette.success),
          ),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

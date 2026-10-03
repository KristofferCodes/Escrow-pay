import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/money.dart';
import '../../core/qr_payload.dart';
import '../../core/release_code.dart';
import '../../solana/release_scan_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../widgets/confirm_burst.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/scan_frame.dart';

/// Seller side of the handover: scan the buyer's code and get paid.
class ReleaseScanScreen extends ConsumerStatefulWidget {
  const ReleaseScanScreen({super.key});

  @override
  ConsumerState<ReleaseScanScreen> createState() => _ReleaseScanScreenState();
}

class _ReleaseScanScreenState extends ConsumerState<ReleaseScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _handled = false;
  String? _rejection;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final payload = ReleasePayload.decode(raw);
      if (payload != null) {
        _handled = true;
        await HapticFeedback.mediumImpact();
        await _controller.stop();
        if (!mounted) return;

        await ref.read(releaseScanControllerProvider.notifier).redeem(payload);
        return;
      }

      // Tell the two kinds of code apart, so scanning the wrong one says why
      // instead of appearing to do nothing.
      final reason = EscrowOffer.decode(raw) != null
          ? 'That is a listing code, not a release code. Ask the buyer to '
                'tap "Show release code".'
          : 'That is not an Escrow Pay release code.';

      if (mounted && _rejection != reason) {
        setState(() => _rejection = reason);
      }
    }
  }

  Future<void> _scanAgain() async {
    ref.read(releaseScanControllerProvider.notifier).reset();
    setState(() {
      _handled = false;
      _rejection = null;
    });
    try {
      await _controller.start();
    } on Object {
      // A failure re-renders through errorBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(releaseScanControllerProvider);
    final text = Theme.of(context).textTheme;

    // Confirmation is the only thing that unlocks the success state, and the
    // haptic with it.
    ref.listen(releaseScanControllerProvider, (previous, next) {
      if (next.confirmed && !(previous?.confirmed ?? false)) {
        HapticFeedback.heavyImpact();
      }
    });

    final showingResult =
        scan.submitting || scan.signature != null || scan.error != null;

    return Scaffold(
      backgroundColor: Palette.void_,
      appBar: AppBar(title: const Text('Scan release code')),
      extendBodyBehindAppBar: true,
      body: showingResult
          ? _Result(scan: scan, onScanAgain: _scanAgain)
          : Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                Center(child: ScanFrame(locked: _handled)),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 48,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: _rejection == null
                        ? Text(
                            key: const ValueKey('hint'),
                            'Ask the buyer to show their release code once '
                            'they have checked the item.',
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              color: Palette.textPrimary,
                            ),
                          )
                        : Container(
                            key: const ValueKey('rejection'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: Radii.control,
                              color: Palette.warning.withValues(alpha: 0.14),
                              border: Border.all(
                                color: Palette.warning.withValues(alpha: 0.42),
                              ),
                            ),
                            child: Text(
                              _rejection!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Palette.warning,
                                fontSize: 13,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Everything after the scan. Success is deliberately withheld until the
/// chain confirms — handing the item over on an unconfirmed release is how a
/// seller loses both.
class _Result extends StatelessWidget {
  const _Result({required this.scan, required this.onScanAgain});

  final ReleaseScanState scan;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final amount = scan.escrow?.amount ?? 0;

    final (icon, tint, title, body) = switch (scan) {
      ReleaseScanState(confirmed: true) => (
        Icons.verified_rounded,
        Palette.success,
        'Paid',
        'The escrow has settled onchain. Hand over the item.',
      ),
      ReleaseScanState(error: final e?) when !scan.pending => (
        Icons.error_outline_rounded,
        Palette.danger,
        'Could not release',
        e,
      ),
      ReleaseScanState(pending: true) => (
        Icons.hourglass_top_rounded,
        Palette.warning,
        'Waiting for confirmation',
        'Do not hand over the item yet. This is not final until the chain '
            'confirms it — until then the buyer could still refund.',
      ),
      _ => (
        Icons.sync_rounded,
        Palette.cyan,
        'Releasing…',
        'Approve the transaction in your wallet.',
      ),
    };

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConfirmBurst(
                // Only a confirmed release earns the celebration.
                trigger: scan.confirmed ? 'paid' : null,
                color: Palette.success,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: tint.withValues(alpha: 0.4)),
                  ),
                  child: Icon(icon, size: 34, color: tint),
                ),
              ),
              Gap.lg,
              if (scan.confirmed) ...[
                Text(Money.sol(amount), style: AppType.amount(size: 34)),
                Gap.sm,
              ],
              Text(title, style: text.titleLarge, textAlign: TextAlign.center),
              Gap.sm,
              Text(body, textAlign: TextAlign.center, style: text.bodyMedium),
              Gap.xl,

              if (scan.confirmed)
                GradientButton(
                  label: 'Done',
                  icon: Icons.check_rounded,
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                )
              else if (!scan.submitting)
                GradientButton(
                  label: 'Scan again',
                  icon: Icons.qr_code_scanner_rounded,
                  onPressed: onScanAgain,
                ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 260.ms),
    );
  }
}

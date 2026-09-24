import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/qr_payload.dart';
import '../../solana/escrow_controller.dart';
import '../../solana/wallet_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../widgets/scan_frame.dart';
import '../status/escrow_status_screen.dart';

/// Buyer side. Points the camera at the seller's code and hands the decoded
/// offer to the status screen.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Latched once a valid offer is found. The camera keeps delivering frames
  /// for a moment after the route push starts, and without this the screen
  /// tries to navigate several times.
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

      final offer = EscrowOffer.decode(raw);
      if (offer == null) {
        if (mounted && _rejection == null) {
          setState(() => _rejection = 'That is not an Escrow Pay code.');
        }
        continue;
      }

      final cluster = ref.read(clusterProvider);
      if (offer.cluster != cluster.id) {
        if (mounted) {
          setState(
            () => _rejection =
                'This code is for ${offer.cluster}. The app is on '
                '${cluster.id}.',
          );
        }
        continue;
      }

      _handled = true;
      await HapticFeedback.mediumImpact();
      await _controller.stop();
      if (!mounted) return;

      unawaited(ref.read(escrowControllerProvider.notifier).adopt(offer));
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const EscrowStatusScreen()),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Palette.void_,
      appBar: AppBar(
        title: const Text('Scan to pay'),
        actions: [
          IconButton(
            onPressed: _controller.toggleTorch,
            icon: const Icon(Icons.flashlight_on_outlined),
            tooltip: 'Torch',
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraProblem(error: error),
          ),

          // The frame paints its own scrim, so it must sit above the preview.
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
                      'Point at the seller’s code. You will confirm the '
                      'amount before anything is signed.',
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

class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.error});
  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;

    return ColoredBox(
      color: Palette.void_,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                denied
                    ? Icons.no_photography_outlined
                    : Icons.videocam_off_outlined,
                size: 40,
                color: Palette.textMuted,
              ),
              Gap.md,
              Text(
                denied ? 'Camera access is off' : 'The camera could not start',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Gap.sm,
              Text(
                denied
                    ? 'Escrow Pay needs the camera to read the seller’s QR '
                          'code. Enable it in system settings and come back.'
                    : error.errorDetails?.message ?? 'Try relaunching the app.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

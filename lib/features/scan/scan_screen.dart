import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/qr_payload.dart';
import '../../solana/escrow_controller.dart';
import '../../solana/wallet_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../widgets/gradient_button.dart';
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

  /// Bumped to force a fresh MobileScanner after a permission change.
  int _cameraAttempt = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Rebuilds the preview after permission is granted. `start()` on a
  /// controller that failed to initialise is not enough — MobileScanner keeps
  /// showing the error until the widget is recreated.
  Future<void> _restartCamera() async {
    setState(() => _cameraAttempt++);
    try {
      await _controller.start();
    } on Object {
      // A second failure re-renders the same screen through errorBuilder.
    }
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
            key: ValueKey(_cameraAttempt),
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) =>
                _CameraProblem(error: error, onRetry: _restartCamera),
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

/// Shown when the camera will not start.
///
/// The old version told the user to go to system settings, which is the one
/// thing most people will not do. Android only shows the permission dialog
/// again if the user has not permanently denied it, so this asks directly
/// first and falls back to opening settings only when Android will no longer
/// prompt.
class _CameraProblem extends ConsumerStatefulWidget {
  const _CameraProblem({required this.error, required this.onRetry});

  final MobileScannerException error;

  /// Restarts the scanner once permission has actually been granted.
  final Future<void> Function() onRetry;

  @override
  ConsumerState<_CameraProblem> createState() => _CameraProblemState();
}

class _CameraProblemState extends ConsumerState<_CameraProblem> {
  bool _busy = false;

  /// True once Android stops showing the dialog, which is the only point at
  /// which sending someone to settings is the right advice.
  bool _mustUseSettings = false;

  bool get _denied =>
      widget.error.errorCode == MobileScannerErrorCode.permissionDenied;

  Future<void> _requestAccess() async {
    setState(() => _busy = true);
    try {
      final status = await Permission.camera.request();

      if (status.isGranted || status.isLimited) {
        await widget.onRetry();
        return;
      }

      // permanentlyDenied means Android will not show the dialog again;
      // restricted means policy forbids it outright.
      if (mounted && (status.isPermanentlyDenied || status.isRestricted)) {
        setState(() => _mustUseSettings = true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final title = !_denied
        ? 'The camera could not start'
        : _mustUseSettings
        ? 'Camera access is blocked'
        : 'Escrow Pay needs the camera';

    final body = !_denied
        ? widget.error.errorDetails?.message ??
              'Something else may be using the camera. Close other apps and '
                  'try again.'
        : _mustUseSettings
        ? 'Android will not ask again, so camera access has to be switched on '
              'in Settings. It is one toggle — we will open the page for you.'
        : 'It is only used to read the seller’s QR code, and only while this '
              'screen is open.';

    return ColoredBox(
      color: Palette.void_,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  gradient: Palette.accentSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: Palette.hairlineStrong),
                ),
                child: Icon(
                  _denied
                      ? Icons.photo_camera_outlined
                      : Icons.videocam_off_outlined,
                  size: 30,
                  color: Palette.cyan,
                ),
              ),
              Gap.lg,
              Text(title, style: text.titleLarge, textAlign: TextAlign.center),
              Gap.sm,
              Text(body, textAlign: TextAlign.center, style: text.bodyMedium),
              Gap.xl,

              if (!_denied)
                GradientButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  busy: _busy,
                  onPressed: () async {
                    setState(() => _busy = true);
                    await widget.onRetry();
                    if (mounted) setState(() => _busy = false);
                  },
                )
              else if (_mustUseSettings)
                GradientButton(
                  label: 'Open settings',
                  icon: Icons.settings_outlined,
                  busy: _busy,
                  onPressed: () async {
                    await openAppSettings();
                    // Android does not tell us when they come back, so
                    // re-check on the next frame the user triggers.
                    if (mounted) setState(() => _mustUseSettings = false);
                  },
                )
              else
                GradientButton(
                  label: 'Allow camera access',
                  icon: Icons.photo_camera_outlined,
                  busy: _busy,
                  onPressed: _requestAccess,
                ),

              Gap.md,
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

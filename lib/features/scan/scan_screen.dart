import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
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

  /// Set while the wallet handoff is in flight, so the scanner shows what is
  /// happening instead of appearing to freeze on a stopped camera.
  bool _connecting = false;

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

      // Connect before leaving this screen. Doing it after navigating meant
      // the wallet handoff raced the route change, and a failure landed the
      // user on a status screen with nothing to act on — it read as the app
      // cutting out. Here, a failure keeps them on the scanner with a retry.
      if (!await _ensureWallet()) return;
      if (!mounted) return;

      unawaited(ref.read(escrowControllerProvider.notifier).adopt(offer));
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const EscrowStatusScreen()),
      );
      return;
    }
  }

  /// Returns true once a wallet is attached. Prompts for one if needed —
  /// scanning a code is a clear enough signal of intent that making the user
  /// find a separate Connect button first is just friction.
  Future<bool> _ensureWallet() async {
    final wallet = ref.read(walletControllerProvider);
    if (wallet.isConnected) return true;

    setState(() => _connecting = true);
    final session = await ref.read(walletControllerProvider.notifier).connect();
    if (!mounted) return false;

    setState(() => _connecting = false);
    if (session != null) return true;

    // Failed or dismissed: let them try again rather than stranding them.
    setState(() => _handled = false);
    try {
      await _controller.start();
    } on Object {
      // Re-renders through errorBuilder if the camera will not restart.
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final wallet = ref.watch(walletControllerProvider);

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
              child: _connecting
                  ? const _ScanNotice(
                      key: ValueKey('connecting'),
                      tint: Palette.cyan,
                      message: 'Opening your wallet…',
                    )
                  : wallet.error != null
                  ? _WalletTrouble(
                      key: const ValueKey('wallet'),
                      message: wallet.error!,
                      noWallet: wallet.noWalletInstalled,
                    )
                  : _rejection == null
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
/// A short status line over the camera view.
class _ScanNotice extends StatelessWidget {
  const _ScanNotice({required this.message, required this.tint, super.key});

  final String message;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: Radii.control,
        color: tint.withValues(alpha: 0.14),
        border: Border.all(color: tint.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(tint),
            ),
          ),
          Gap.md,
          Flexible(
            child: Text(message, style: TextStyle(color: tint, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// Shown when the wallet handoff failed, right where the user is — with the
/// one action that helps when nothing can answer the intent.
class _WalletTrouble extends ConsumerWidget {
  const _WalletTrouble({
    required this.message,
    required this.noWallet,
    super.key,
  });

  final String message;
  final bool noWallet;

  static final _solflare = Uri.parse(
    'https://play.google.com/store/apps/details?id=com.solflare.mobile',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: Radii.control,
        color: Palette.warning.withValues(alpha: 0.14),
        border: Border.all(color: Palette.warning.withValues(alpha: 0.42)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Palette.warning,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (noWallet) ...[
            Gap.sm,
            FilledButton.icon(
              onPressed: () =>
                  launchUrl(_solflare, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download_rounded, size: 17),
              label: const Text('Install Solflare'),
              style: FilledButton.styleFrom(
                backgroundColor: Palette.warning,
                foregroundColor: Palette.void_,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ] else ...[
            Gap.sm,
            Text(
              'Point at the code again to retry.',
              style: TextStyle(
                color: Palette.warning.withValues(alpha: 0.8),
                fontSize: 11.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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

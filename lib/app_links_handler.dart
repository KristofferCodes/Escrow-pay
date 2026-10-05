import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/deep_link.dart';
import 'features/scan/release_scan_screen.dart';
import 'features/status/escrow_status_screen.dart';
import 'solana/escrow_controller.dart';
import 'solana/release_scan_controller.dart';
import 'solana/wallet_controller.dart';

/// Routes incoming `escrowpay:` links.
///
/// A shared link is only useful if tapping it does something. This catches
/// both the link that launched the app and any that arrive while it is
/// running, works out which kind it is, and sends it where it belongs —
/// a listing to the buyer's review screen, a release code to redemption.
class AppLinksHandler extends ConsumerStatefulWidget {
  const AppLinksHandler({
    required this.navigatorKey,
    required this.child,
    super.key,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<AppLinksHandler> createState() => _AppLinksHandlerState();
}

class _AppLinksHandlerState extends ConsumerState<AppLinksHandler> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// Guards against handling the launch link twice — once from
  /// getInitialLink and again from the stream.
  String? _lastHandled;

  @override
  void initState() {
    super.initState();
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => _handle(uri.toString()),
      // A malformed link is not worth crashing over.
      onError: (_) {},
    );
    unawaited(_handleInitial());
  }

  Future<void> _handleInitial() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) await _handle(uri.toString());
    } on Object {
      // No launch link, or the platform could not supply one.
    }
  }

  Future<void> _handle(String raw) async {
    if (raw == _lastHandled) return;
    _lastHandled = raw;

    final link = DeepLink.parse(raw) ?? DeepLink.findIn(raw);
    final navigator = widget.navigatorKey.currentState;
    if (link == null || navigator == null) return;

    switch (link) {
      case OfferLink(:final offer):
        if (!_clusterMatches(offer.cluster, navigator)) return;
        unawaited(ref.read(escrowControllerProvider.notifier).adopt(offer));
        await navigator.push(
          MaterialPageRoute(builder: (_) => const EscrowStatusScreen()),
        );

      case ReleaseLink(:final payload):
        if (!_clusterMatches(payload.cluster, navigator)) return;

        // Needs a wallet to pay the fee; prompting here keeps the failure
        // off the result screen.
        final session = await ref
            .read(walletControllerProvider.notifier)
            .require();
        if (session == null) return;

        unawaited(
          ref.read(releaseScanControllerProvider.notifier).redeem(payload),
        );
        await navigator.push(
          MaterialPageRoute(builder: (_) => const ReleaseScanScreen()),
        );
    }
  }

  /// A devnet link opened on a mainnet build would derive a different escrow
  /// and quietly fail, so say so instead.
  bool _clusterMatches(String linkCluster, NavigatorState navigator) {
    final cluster = ref.read(clusterProvider);
    if (linkCluster == cluster.id) return true;

    final messenger = ScaffoldMessenger.maybeOf(navigator.context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          'That link is for $linkCluster. This app is on ${cluster.id}.',
        ),
      ),
    );
    return false;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

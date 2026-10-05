import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/money.dart';
import '../../solana/listings_controller.dart';
import '../../solana/wallet_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../widgets/circuit_backdrop.dart';
import '../../widgets/escrow_mark.dart';
import '../../widgets/glass_panel.dart';
import '../create_listing/create_listing_screen.dart';
import '../history/history_screen.dart';
import '../listings/listings_screen.dart';
import '../scan/release_scan_screen.dart';
import '../scan/scan_screen.dart';

/// The fork in the road: sell or buy.
///
/// Both roles live in one app because a demo has to show both sides, and
/// because the same person is a seller one week and a buyer the next.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletControllerProvider);
    final cluster = ref.watch(clusterProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: CircuitBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              // Scrolls only when it has to; on a tall phone the layout is
              // unchanged. Before this a third action card overflowed the
              // bottom on anything shorter.
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Expanded, not Flexible beside a Spacer: a Spacer is
                        // itself an Expanded, so it claimed every spare pixel
                        // and truncated the wordmark to "Escro…".
                        const Expanded(child: _Mark()),
                        _ListingsButton(
                          onTap: () => Navigator.of(
                            context,
                          ).push(_fade(const ListingsScreen())),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(
                            context,
                          ).push(_fade(const HistoryScreen())),
                          icon: const Icon(
                            Icons.receipt_long_outlined,
                            size: 19,
                          ),
                          color: Palette.textSecondary,
                          tooltip: 'Your trades',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                        Gap.sm,
                        _ClusterBadge(label: cluster.label),
                      ],
                    ),
                    Gap.xl,

                    Text('ESCROW PAY', style: text.labelSmall),
                    Gap.sm,
                    Text(
                          'Trade with\nstrangers safely.',
                          style: text.displaySmall,
                        )
                        .animate()
                        .fadeIn(duration: 500.ms)
                        .slideY(begin: 0.16, curve: Curves.easeOutCubic),
                    Gap.md,
                    Text(
                      'Funds sit in a program-controlled account until the buyer '
                      'confirms the goods arrived. No middleman holds them — not '
                      'even us.',
                      style: text.bodyLarge,
                    ).animate(delay: 120.ms).fadeIn(duration: 450.ms),

                    Gap.xl,
                    Gap.lg,

                    _RoleCard(
                      eyebrow: 'SELLING',
                      title: 'Create a listing',
                      blurb: 'Set a price and show the buyer a QR code.',
                      icon: Icons.qr_code_2_rounded,
                      onTap: () => Navigator.of(
                        context,
                      ).push(_fade(const CreateListingScreen())),
                    ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.12),
                    Gap.md,
                    _RoleCard(
                      eyebrow: 'BUYING',
                      title: 'Scan to pay',
                      blurb: "Scan the seller's code and fund the escrow.",
                      icon: Icons.center_focus_strong_rounded,
                      onTap: () =>
                          Navigator.of(context).push(_fade(const ScanScreen())),
                    ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.12),
                    Gap.md,
                    _RoleCard(
                      eyebrow: 'HANDING OVER',
                      title: 'Scan release code',
                      blurb: 'Get paid the moment the buyer shows their code.',
                      icon: Icons.qr_code_scanner_rounded,
                      onTap: () => Navigator.of(
                        context,
                      ).push(_fade(const ReleaseScanScreen())),
                    ).animate(delay: 380.ms).fadeIn().slideY(begin: 0.12),

                    Gap.lg,
                    _WalletStrip(wallet: wallet),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Route<void> _fade(Widget page) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
}

class _Mark extends StatelessWidget {
  const _Mark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // The app's own monogram, not a stock padlock.
        const EscrowMark(size: 26),
        Gap.sm,
        Flexible(
          child: Text(
            'Escrow Pay',
            style: Theme.of(context).textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ClusterBadge extends StatelessWidget {
  const _ClusterBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: Radii.chip,
        border: Border.all(color: Palette.hairlineStrong),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppType.mono(size: 10, color: Palette.textMuted, spacing: 1.1),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.eyebrow,
    required this.title,
    required this.blurb,
    required this.icon,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final String blurb;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.panel,
      child: GlassPanel(
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: Palette.accentSoft,
                borderRadius: Radii.control,
                border: Border.all(color: Palette.hairlineStrong),
              ),
              child: Icon(icon, color: Palette.cyan, size: 22),
            ),
            Gap.md,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(eyebrow, style: text.labelSmall),
                  Gap.xs,
                  Text(title, style: text.titleLarge),
                  Gap.xs,
                  Text(blurb, style: text.bodyMedium),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: Palette.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletStrip extends ConsumerWidget {
  const _WalletStrip({required this.wallet});
  final WalletState wallet;

  /// Solflare is the wallet Solana Mobile's own docs point developers at, and
  /// it supports devnet, which this build needs.
  static final _solflare = Uri.parse(
    'https://play.google.com/store/apps/details?id=com.solflare.mobile',
  );

  Future<void> _installWallet(BuildContext context) async {
    final opened = await launchUrl(
      _solflare,
      mode: LaunchMode.externalApplication,
    );
    if (opened || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not open the Play Store. Search for "Solflare".'),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(walletControllerProvider.notifier);
    final session = wallet.session;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: session != null
          ? Row(
              key: const ValueKey('connected'),
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: Palette.success,
                ),
                Gap.sm,
                Text(
                  Money.shortAddress(session.address.value, edge: 5),
                  style: AppType.mono(size: 12.5),
                ),
                const Spacer(),
                TextButton(
                  onPressed: controller.disconnect,
                  child: const Text('Disconnect'),
                ),
              ],
            )
          : Column(
              key: const ValueKey('disconnected'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Previously the failure was stored and never drawn, so a tap
                // with no wallet installed just stopped the spinner and looked
                // like a dead button.
                if (wallet.error != null) ...[
                  _WalletProblem(
                    message: wallet.error!,
                    actionLabel: wallet.noWalletInstalled
                        ? 'Install Solflare'
                        : null,
                    onAction: wallet.noWalletInstalled
                        ? () => _installWallet(context)
                        : null,
                    onDismiss: controller.clearError,
                  ),
                  Gap.sm,
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: wallet.connecting ? null : controller.connect,
                    icon: wallet.connecting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 16,
                          ),
                    label: Text(
                      wallet.connecting
                          ? 'Opening wallet…'
                          : wallet.error != null
                          ? 'Try again'
                          : 'Connect a wallet',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A failed wallet handoff, with the one action that can fix it when there is
/// one. Warning rather than error: nothing is broken, something is missing.
class _WalletProblem extends StatelessWidget {
  const _WalletProblem({
    required this.message,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        borderRadius: Radii.control,
        color: Palette.warning.withValues(alpha: 0.10),
        border: Border.all(color: Palette.warning.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 17,
                color: Palette.warning,
              ),
              Gap.md,
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Palette.warning,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
              InkWell(
                onTap: onDismiss,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: Palette.warning,
                  ),
                ),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            Gap.sm,
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.download_rounded, size: 17),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.warning,
                  foregroundColor: Palette.void_,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 220.ms).slideY(begin: -0.1);
  }
}

/// Listings entry point, badged when a buyer has funded something the seller
/// has not collected — the signal that previously required opening the app
/// and hunting for a refresh button.
class _ListingsButton extends ConsumerWidget {
  const _ListingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(
      listingsControllerProvider.select((s) => s.awaitingCollection),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: onTap,
          icon: const Icon(Icons.sell_outlined, size: 19),
          color: Palette.textSecondary,
          tooltip: 'Your listings',
        ),
        if (waiting > 0)
          Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Palette.cyan,
                    borderRadius: Radii.chip,
                  ),
                  child: Text(
                    '$waiting',
                    style: const TextStyle(
                      color: Palette.void_,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .fadeIn()
              .scaleXY(
                begin: 0.9,
                end: 1.08,
                duration: 900.ms,
                curve: Curves.easeInOut,
              ),
      ],
    );
  }
}

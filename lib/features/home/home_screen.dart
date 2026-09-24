import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../solana/wallet_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../widgets/circuit_backdrop.dart';
import '../../widgets/glass_panel.dart';
import '../create_listing/create_listing_screen.dart';
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _Mark(),
                    const Spacer(),
                    _ClusterBadge(label: cluster.label),
                  ],
                ),
                const Spacer(),

                Text('ESCROW PAY', style: text.labelSmall),
                Gap.sm,
                Text('Trade with\nstrangers safely.', style: text.displaySmall)
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

                const Spacer(flex: 2),

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

                Gap.lg,
                _WalletStrip(wallet: wallet),
              ],
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
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            gradient: Palette.accent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.lock_rounded, size: 16, color: Colors.white),
        ),
        Gap.sm,
        Text('Escrow Pay', style: Theme.of(context).textTheme.titleMedium),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(walletControllerProvider.notifier);
    final session = wallet.session;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: session == null
          ? TextButton.icon(
              key: const ValueKey('disconnected'),
              onPressed: wallet.connecting ? null : controller.connect,
              icon: wallet.connecting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.account_balance_wallet_outlined, size: 16),
              label: Text(
                wallet.connecting ? 'Opening wallet…' : 'Connect a wallet',
              ),
            )
          : Row(
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
            ),
    );
  }
}

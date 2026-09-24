import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/escrow.dart';
import '../../core/money.dart';
import '../../solana/escrow_controller.dart';
import '../../solana/wallet_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../widgets/address_chip.dart';
import '../../widgets/circuit_backdrop.dart';
import '../../widgets/confirm_burst.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/shimmer_block.dart';
import '../../widgets/status_ring.dart';

/// Where the money is, and what the buyer can do about it.
///
/// One screen covers all four states rather than routing between them: the
/// ring and the action row change, the context around them does not, so the
/// user never loses their place mid-trade.
class EscrowStatusScreen extends ConsumerWidget {
  const EscrowStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(escrowControllerProvider);
    final controller = ref.read(escrowControllerProvider.notifier);
    final cluster = ref.watch(clusterProvider);
    final accent = Palette.forState(view.state.key);

    // Confirmations are worth feeling, not just seeing.
    ref.listen(escrowControllerProvider, (previous, next) {
      if (previous?.confirmToken != next.confirmToken &&
          next.confirmToken != null) {
        HapticFeedback.heavyImpact();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escrow'),
        actions: [
          IconButton(
            onPressed: view.busy ? null : controller.reload,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh from chain',
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: CircuitBackdrop(
        glowColor: accent,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: controller.reload,
            backgroundColor: Palette.surfaceRaised,
            color: accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (view.loading && view.escrow == null && view.offer == null)
                  const EscrowSkeleton()
                else ...[
                  _Ring(view: view, accent: accent),
                  Gap.xl,
                  _Headline(view: view, accent: accent),
                  Gap.lg,
                  _Details(view: view, cluster: cluster.label),
                  if (view.error != null) ...[
                    Gap.md,
                    _ErrorPanel(
                      message: view.error!,
                      onDismiss: controller.clearError,
                    ),
                  ],
                  Gap.xl,
                  _Actions(view: view, controller: controller),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.view, required this.accent});

  final EscrowView view;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConfirmBurst(
        trigger: view.confirmToken,
        color: accent,
        child: StatusRing(
          state: view.state,
          pending: view.busy,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Amounts are mono and tabular, so the digits do not shuffle
              // when the value updates from the chain.
              Text(
                Money.solLabel(view.amount),
                style: AppType.amount(size: 38),
              ),
              Gap.xs,
              Text(
                'SOL',
                style: AppType.mono(
                  size: 12,
                  color: Palette.textMuted,
                  spacing: 3,
                ),
              ),
              Gap.md,
              StatePill(label: view.state.name, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline({required this.view, required this.accent});

  final EscrowView view;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(sizeFactor: animation, child: child),
      ),
      child: Column(
        key: ValueKey(view.state),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(view.state.label, style: text.headlineMedium),
          Gap.sm,
          Text(view.state.blurb, style: text.bodyLarge),
        ],
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.view, required this.cluster});

  final EscrowView view;
  final String cluster;

  @override
  Widget build(BuildContext context) {
    final escrow = view.escrow;
    final mono = AppType.mono(size: 13);

    return GlassPanel(
      accent: view.escrow == null ? null : Palette.forState(view.state.key),
      child: Column(
        children: [
          DetailRow(
            label: 'Item',
            value: view.offer?.item ?? '—',
            valueStyle: Theme.of(context).textTheme.titleMedium,
          ),
          const Divider(height: 18),
          DetailRow(
            label: 'Amount',
            value: Money.sol(view.amount),
            valueStyle: AppType.mono(
              size: 13.5,
              color: Palette.textPrimary,
              weight: FontWeight.w600,
            ),
          ),
          const Divider(height: 18),
          if (view.seller != null) ...[
            DetailRow(
              label: 'Seller',
              value: '',
              trailing: AddressChip(address: view.seller!),
            ),
            const Divider(height: 18),
          ],
          if (view.address != null) ...[
            DetailRow(
              label: 'Escrow',
              value: '',
              trailing: AddressChip(
                address: view.address!.value,
                accent: Palette.cyan,
              ),
            ),
            const Divider(height: 18),
          ],
          if (escrow != null) ...[
            DetailRow(
              label: 'Opened',
              value: _timestamp(escrow.createdAt),
              valueStyle: mono,
            ),
            const Divider(height: 18),
          ],
          DetailRow(label: 'Network', value: cluster, valueStyle: mono),
          if (view.lastSignature != null) ...[
            const Divider(height: 18),
            DetailRow(
              label: 'Last tx',
              value: '',
              trailing: AddressChip(
                address: view.lastSignature!,
                accent: Palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _timestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)} ${two(value.hour)}:'
        '${two(value.minute)}';
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.view, required this.controller});

  final EscrowView view;
  final EscrowController controller;

  @override
  Widget build(BuildContext context) {
    // Before the escrow exists onchain, the only move is to fund it.
    if (view.escrow == null) {
      return GradientButton(
        label: 'Fund the escrow',
        icon: Icons.lock_rounded,
        busy: view.busy,
        onPressed: view.offer == null ? null : controller.fund,
      ).animate().fadeIn();
    }

    if (view.state.isSettled) {
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                view.state == EscrowState.released
                    ? Icons.verified_rounded
                    : Icons.undo_rounded,
                size: 17,
                color: Palette.forState(view.state.key),
              ),
              Gap.sm,
              Text(
                view.state == EscrowState.released
                    ? 'Settled onchain'
                    : 'Refunded onchain',
                style: TextStyle(color: Palette.forState(view.state.key)),
              ),
            ],
          ),
          Gap.lg,
          OutlineButton(
            label: 'Done',
            icon: Icons.check_rounded,
            onPressed: () {
              controller.clear();
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ).animate().fadeIn(duration: 400.ms);
    }

    return Column(
      children: [
        GradientButton(
          label: 'Confirm receipt & release',
          icon: Icons.check_circle_outline_rounded,
          busy: view.busy,
          onPressed: view.canConfirm ? controller.confirmReceipt : null,
        ),
        Gap.md,
        OutlineButton(
          label: 'Something is wrong — refund me',
          icon: Icons.undo_rounded,
          color: Palette.warning,
          onPressed: view.canRefund
              ? () => _confirmRefund(context, controller)
              : null,
        ),
        Gap.md,
        Text(
          'Only you can move these funds, and only to the seller or back to '
          'yourself.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ).animate().fadeIn();
  }

  /// Refunding is not destructive, but it does end the trade — worth one tap
  /// of friction so it cannot happen by accident during a handover.
  Future<void> _confirmRefund(
    BuildContext context,
    EscrowController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.surfaceRaised,
        shape: const RoundedRectangleBorder(borderRadius: Radii.panel),
        title: const Text('Refund yourself?'),
        content: const Text(
          'This closes the trade and returns the funds to your wallet. The '
          'seller will not be paid.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep in escrow'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Refund',
              style: TextStyle(color: Palette.warning),
            ),
          ),
        ],
      ),
    );

    if (confirmed ?? false) await controller.refund();
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        borderRadius: Radii.control,
        color: Palette.danger.withValues(alpha: 0.10),
        border: Border.all(color: Palette.danger.withValues(alpha: 0.38)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: Palette.danger,
          ),
          Gap.md,
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Palette.danger, fontSize: 13),
            ),
          ),
          InkWell(
            onTap: onDismiss,
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Palette.danger,
            ),
          ),
        ],
      ),
    ).animate().fadeIn().shake(hz: 3, offset: const Offset(2, 0));
  }
}

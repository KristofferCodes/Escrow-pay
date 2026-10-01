import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/escrow.dart';
import '../../core/money.dart';
import '../../solana/history_controller.dart';
import '../../solana/wallet_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../widgets/address_chip.dart';
import '../../widgets/circuit_backdrop.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/shimmer_block.dart';

/// Everything this wallet has bought or sold.
///
/// Read from the chain each time rather than cached locally: the escrow
/// accounts are the record, they outlive the install, and they follow the
/// wallet to another device.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyControllerProvider);
    final session = ref.watch(walletControllerProvider).session;

    return Scaffold(
      appBar: AppBar(title: const Text('Your trades')),
      extendBodyBehindAppBar: true,
      body: CircuitBackdrop(
        glowColor: Palette.indigo,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: ref.read(historyControllerProvider.notifier).refresh,
            backgroundColor: Palette.surfaceRaised,
            color: Palette.cyan,
            child: switch (history) {
              AsyncLoading() => const _HistorySkeleton(),
              AsyncError(:final error) => _HistoryMessage(
                icon: Icons.cloud_off_rounded,
                title: 'Could not read your history',
                body: '$error',
              ),
              AsyncData() when session == null => const _HistoryMessage(
                icon: Icons.account_balance_wallet_outlined,
                title: 'No wallet connected',
                body: 'Connect a wallet to see the trades it has been part of.',
              ),
              AsyncData(:final value) when value.isEmpty =>
                const _HistoryMessage(
                  icon: Icons.receipt_long_outlined,
                  title: 'Nothing here yet',
                  body:
                      'Escrows you fund or get paid from will show up here, '
                      'read straight from the chain.',
                ),
              AsyncData(:final value) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 80, 20, 32),
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: value.length + 1,
                separatorBuilder: (_, _) => Gap.md,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _Summary(
                      escrows: value,
                      wallet: session!.address.value,
                    );
                  }
                  final escrow = value[index - 1];
                  return _TradeTile(
                        escrow: escrow,
                        side: escrow.sideFor(session!.address.value),
                      )
                      .animate(delay: (index * 40).ms)
                      .fadeIn()
                      .slideY(begin: 0.08);
                },
              ),
            },
          ),
        ),
      ),
    );
  }
}

/// Totals, so the list answers "how much have I moved" at a glance.
class _Summary extends StatelessWidget {
  const _Summary({required this.escrows, required this.wallet});

  final List<Escrow> escrows;
  final String wallet;

  @override
  Widget build(BuildContext context) {
    var bought = 0;
    var sold = 0;
    var open = 0;

    for (final escrow in escrows) {
      if (!escrow.state.isSettled) open++;
      // Only released escrows actually moved money; refunded ones came back.
      if (escrow.state != EscrowState.released) continue;
      if (escrow.sideFor(wallet) == TradeSide.bought) {
        bought += escrow.amount;
      } else {
        sold += escrow.amount;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          _Stat(
            label: 'SPENT',
            value: Money.solLabel(bought),
            tint: Palette.violet,
          ),
          Gap.md,
          _Stat(
            label: 'EARNED',
            value: Money.solLabel(sold),
            tint: Palette.success,
          ),
          Gap.md,
          _Stat(label: 'OPEN', value: '$open', tint: Palette.cyan),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.tint});

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppType.mono(
                size: 9.5,
                color: Palette.textMuted,
                spacing: 1.2,
              ),
            ),
            Gap.xs,
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: AppType.amount(size: 22, color: tint)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TradeTile extends StatelessWidget {
  const _TradeTile({required this.escrow, required this.side});

  final Escrow escrow;
  final TradeSide side;

  @override
  Widget build(BuildContext context) {
    final accent = Palette.forState(escrow.state.key);
    final bought = side == TradeSide.bought;

    // The counterparty is whoever you weren't.
    final counterparty = bought ? escrow.seller : escrow.buyer;

    return GlassPanel(
      padding: const EdgeInsets.all(16),
      accent: escrow.state.isSettled ? null : accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.13),
                  borderRadius: Radii.control,
                ),
                child: Icon(
                  bought ? Icons.south_west_rounded : Icons.north_east_rounded,
                  size: 17,
                  color: accent,
                ),
              ),
              Gap.md,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bought ? 'Bought' : 'Sold',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      _when(escrow.createdAt),
                      style: AppType.mono(size: 11, color: Palette.textMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    // Sign it from this wallet's point of view: a release you
                    // bought is money out, one you sold is money in.
                    '${escrow.state == EscrowState.released ? (bought ? '−' : '+') : ''}'
                    '${Money.solLabel(escrow.amount)}',
                    style: AppType.mono(
                      size: 14.5,
                      color: escrow.state == EscrowState.released
                          ? (bought ? Palette.textPrimary : Palette.success)
                          : Palette.textSecondary,
                      weight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'SOL',
                    style: AppType.mono(
                      size: 9.5,
                      color: Palette.textMuted,
                      spacing: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Gap.md,
          Row(
            children: [
              StatePill(label: escrow.state.name, color: accent),
              const Spacer(),
              AddressChip(address: counterparty, label: bought ? 'to' : 'from'),
            ],
          ),
        ],
      ),
    );
  }

  static String _when(DateTime value) {
    final now = DateTime.now();
    final delta = now.difference(value);

    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays < 7) return '${delta.inDays}d ago';

    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }
}

class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // A ListView so pull-to-refresh still works on an empty list.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 160, 32, 32),
      children: [
        Icon(icon, size: 34, color: Palette.textMuted),
        Gap.md,
        Text(title, textAlign: TextAlign.center, style: text.titleLarge),
        Gap.sm,
        Text(body, textAlign: TextAlign.center, style: text.bodyMedium),
      ],
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 32),
      children: [
        Row(
          children: List.generate(
            3,
            (i) => const Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 12),
                child: ShimmerBlock(height: 72, borderRadius: Radii.panel),
              ),
            ),
          ),
        ),
        Gap.md,
        for (var i = 0; i < 4; i++) ...[
          const ShimmerBlock(height: 106, borderRadius: Radii.panel),
          Gap.md,
        ],
      ],
    );
  }
}

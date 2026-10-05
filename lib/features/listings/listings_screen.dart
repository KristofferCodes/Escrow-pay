import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/escrow.dart';
import '../../core/listing.dart';
import '../../core/money.dart';
import '../../solana/listings_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../widgets/circuit_backdrop.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/shimmer_block.dart';
import '../create_listing/offer_qr_screen.dart';

/// The seller's open listings.
///
/// Before this, generating a QR and leaving the app lost it — including the
/// nonce, so a buyer still holding the old code could no longer pay.
/// Listings now survive, show whether a buyer has funded them, and can be
/// reshown or reshared.
class ListingsScreen extends ConsumerWidget {
  const ListingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(listingsControllerProvider);
    final controller = ref.read(listingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Your listings')),
      extendBodyBehindAppBar: true,
      body: CircuitBackdrop(
        glowColor: Palette.violet,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: controller.refresh,
            backgroundColor: Palette.surfaceRaised,
            color: Palette.cyan,
            child: listings.loading && listings.listings.isEmpty
                ? const _ListingsSkeleton()
                : listings.listings.isEmpty
                ? const _Empty()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 80, 20, 32),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: listings.listings.length + 1,
                    separatorBuilder: (_, _) => Gap.md,
                    itemBuilder: (context, index) {
                      if (index == 0) return _Header(error: listings.error);

                      final watched = listings.listings[index - 1];
                      return _ListingTile(
                            watched: watched,
                            onForget: () =>
                                controller.remove(watched.listing.offer.nonce),
                          )
                          .animate(delay: (index * 40).ms)
                          .fadeIn()
                          .slideY(begin: 0.08);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          'Kept for 48 hours, then cleared automatically. This list checks '
          'itself — you do not need to refresh.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: Radii.control,
        color: Palette.warning.withValues(alpha: 0.10),
        border: Border.all(color: Palette.warning.withValues(alpha: 0.38)),
      ),
      child: Text(
        error!,
        style: const TextStyle(
          color: Palette.warning,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }
}

class _ListingTile extends StatelessWidget {
  const _ListingTile({required this.watched, required this.onForget});

  final WatchedListing watched;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final offer = watched.listing.offer;

    final (tint, status) = switch (watched.escrow?.state) {
      null => (Palette.textMuted, 'Waiting for a buyer'),
      EscrowState.created => (Palette.violet, 'Opened, not funded yet'),
      EscrowState.funded => (Palette.cyan, 'Paid — funds held in escrow'),
      EscrowState.released => (Palette.success, 'Released to you'),
      EscrowState.refunded => (Palette.warning, 'Refunded to the buyer'),
    };

    return GlassPanel(
      // Only draw the eye while something is actually owed.
      accent: watched.isPaid && !watched.isSettled ? tint : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.item, style: text.titleMedium),
                    Gap.xs,
                    Text(
                      _timeLeft(watched.listing),
                      style: AppType.mono(size: 11, color: Palette.textMuted),
                    ),
                  ],
                ),
              ),
              Text(
                Money.solLabel(offer.lamports),
                style: AppType.mono(
                  size: 15,
                  color: Palette.textPrimary,
                  weight: FontWeight.w700,
                ),
              ),
              Gap.xs,
              Text(
                'SOL',
                style: AppType.mono(size: 9.5, color: Palette.textMuted),
              ),
            ],
          ),
          Gap.md,
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
              ),
              Gap.sm,
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(color: tint, fontSize: 12.5),
                ),
              ),
            ],
          ),
          Gap.md,
          const Divider(height: 1),
          Gap.sm,
          Row(
            children: [
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OfferQrScreen(offer: offer),
                  ),
                ),
                icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                label: const Text('Show code'),
              ),
              const Spacer(),
              TextButton(
                onPressed: onForget,
                child: const Text(
                  'Forget',
                  style: TextStyle(color: Palette.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _timeLeft(Listing listing) {
    final left = listing.timeLeft;
    if (left.isNegative) return 'expired';
    if (left.inHours >= 1) return '${left.inHours}h left';
    return '${left.inMinutes}m left';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 160, 32, 32),
      children: [
        const Icon(Icons.sell_outlined, size: 34, color: Palette.textMuted),
        Gap.md,
        Text(
          'No open listings',
          textAlign: TextAlign.center,
          style: text.titleLarge,
        ),
        Gap.sm,
        Text(
          'Listings you create stay here for 48 hours, so you can reshow the '
          'code and see when a buyer has paid.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
      ],
    );
  }
}

class _ListingsSkeleton extends StatelessWidget {
  const _ListingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 80, 20, 32),
      children: [
        for (var i = 0; i < 3; i++) ...[
          const ShimmerBlock(height: 150, borderRadius: Radii.panel),
          Gap.md,
        ],
      ],
    );
  }
}

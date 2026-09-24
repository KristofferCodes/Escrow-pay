import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/money.dart';
import '../../core/qr_payload.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../widgets/address_chip.dart';
import '../../widgets/circuit_backdrop.dart';
import '../../widgets/glass_panel.dart';

/// The code the buyer scans.
///
/// Nothing has touched the chain at this point — the QR is pure offer data,
/// and the escrow only exists once the buyer funds it. That is why this screen
/// has no pending state and no spinner: there is nothing to wait for.
class OfferQrScreen extends StatelessWidget {
  const OfferQrScreen({required this.offer, super.key});

  final EscrowOffer offer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Show the buyer')),
      extendBodyBehindAppBar: true,
      body: CircuitBackdrop(
        glowColor: Palette.cyan,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
            children: [
              Center(
                child: Column(
                  children: [
                    Text(
                      Money.sol(offer.lamports),
                      style: AppType.amount(size: 36),
                    ),
                    Gap.sm,
                    Text(offer.item, style: text.bodyLarge),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms),

              Gap.lg,

              // The code sits on white: QR contrast is a scanner requirement,
              // not a style choice, and a dark-on-dark code does not read.
              Center(
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: Radii.panel,
                        boxShadow: [
                          BoxShadow(
                            color: Palette.cyan.withValues(alpha: 0.28),
                            blurRadius: 44,
                            spreadRadius: -10,
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: offer.encode(),
                        version: QrVersions.auto,
                        size: 236,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Palette.void_,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Palette.void_,
                        ),
                      ),
                    ),
                  )
                  .animate()
                  .fadeIn(duration: 450.ms, delay: 100.ms)
                  .scaleXY(begin: 0.94, curve: Curves.easeOutBack),

              Gap.xl,

              GlassPanel(
                child: Column(
                  children: [
                    DetailRow(
                      label: 'You receive',
                      value: Money.sol(offer.lamports),
                      valueStyle: AppType.mono(
                        size: 13.5,
                        color: Palette.textPrimary,
                        weight: FontWeight.w600,
                      ),
                    ),
                    const Divider(height: 18),
                    DetailRow(
                      label: 'Paid to',
                      value: Money.shortAddress(offer.seller, edge: 6),
                      valueStyle: AppType.mono(size: 13),
                      trailing: AddressChip(address: offer.seller),
                    ),
                    const Divider(height: 18),
                    DetailRow(
                      label: 'Reference',
                      value: '${offer.nonce}',
                      valueStyle: AppType.mono(size: 12.5),
                    ),
                    const Divider(height: 18),
                    DetailRow(
                      label: 'Network',
                      value: offer.cluster,
                      valueStyle: AppType.mono(size: 12.5),
                    ),
                  ],
                ),
              ).animate(delay: 220.ms).fadeIn().slideY(begin: 0.08),

              Gap.lg,
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.handshake_outlined,
                    size: 17,
                    color: Palette.textMuted,
                  ),
                  Gap.md,
                  Expanded(
                    child: Text(
                      'Hand over the item once you see the escrow funded. The '
                      'buyer releases the funds from their side.',
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

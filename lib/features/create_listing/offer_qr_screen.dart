import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/money.dart';
import '../../core/qr_payload.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../widgets/address_chip.dart';
import '../../widgets/circuit_backdrop.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/gradient_button.dart';

/// The code the buyer scans.
///
/// Nothing has touched the chain at this point — the QR is pure offer data,
/// and the escrow only exists once the buyer funds it. That is why this screen
/// has no pending state and no spinner: there is nothing to wait for.
class OfferQrScreen extends StatelessWidget {
  const OfferQrScreen({required this.offer, super.key});

  final EscrowOffer offer;

  static String _window(Duration d) =>
      d.inHours >= 24 ? '${d.inDays}d' : '${d.inHours}h';

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
                    // The chip already shows the address and the copy
                    // affordance; passing `value` too printed it twice on
                    // the same line.
                    DetailRow(
                      label: 'Paid to',
                      value: '',
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
                      label: 'Refund window',
                      value: _window(offer.timeout),
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
              _ShareRow(offer: offer),

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

/// Ways to get the offer to a buyer who is not standing in front of you, or
/// whose camera will not cooperate.
///
/// The link is the same string the QR encodes, so a buyer who cannot scan can
/// still be handed the identical offer. Both lead to the same escrow — the
/// QR is a convenience, not the protocol.
class _ShareRow extends StatefulWidget {
  const _ShareRow({required this.offer});

  final EscrowOffer offer;

  @override
  State<_ShareRow> createState() => _ShareRowState();
}

class _ShareRowState extends State<_ShareRow> {
  bool _copied = false;

  Future<void> _share() async {
    final offer = widget.offer;
    await SharePlus.instance.share(
      ShareParams(
        subject: 'Escrow Pay — ${offer.item}',
        text:
            'Pay ${Money.sol(offer.lamports)} for "${offer.item}" through '
            'Escrow Pay.\n\n'
            'Open this in Escrow Pay, or scan the code:\n'
            '${offer.encode()}',
      ),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.offer.encode()));
    await HapticFeedback.selectionClick();
    if (!mounted) return;

    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: GradientButton(
                label: 'Share listing',
                icon: Icons.ios_share_rounded,
                onPressed: _share,
              ),
            ),
          ],
        ),
        Gap.sm,
        TextButton.icon(
          onPressed: _copy,
          icon: Icon(
            _copied ? Icons.check_rounded : Icons.link_rounded,
            size: 16,
            color: _copied ? Palette.success : Palette.textSecondary,
          ),
          label: Text(
            _copied ? 'Link copied' : "Copy link (if they can't scan)",
            style: TextStyle(
              color: _copied ? Palette.success : Palette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

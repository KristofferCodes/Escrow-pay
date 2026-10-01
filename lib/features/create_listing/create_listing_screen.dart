import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/qr_payload.dart';
import '../../solana/wallet_controller.dart';
import '../../theme/app_theme.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../../widgets/circuit_backdrop.dart';
import '../../widgets/glass_panel.dart';
import '../../widgets/gradient_button.dart';
import 'offer_qr_screen.dart';

/// Seller side. Two fields and a wallet, which is all the program needs to
/// derive an escrow.
class CreateListingScreen extends ConsumerStatefulWidget {
  const CreateListingScreen({super.key});

  @override
  ConsumerState<CreateListingScreen> createState() =>
      _CreateListingScreenState();
}

class _CreateListingScreenState extends ConsumerState<CreateListingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _item = TextEditingController();
  final _price = TextEditingController();

  /// How long the buyer keeps the right to refund. After it, the seller can
  /// claim — so this is the seller choosing how long to wait to be paid if
  /// the buyer goes quiet.
  int _timeoutSeconds = EscrowOffer.defaultTimeoutSeconds;

  static const _timeoutChoices = <String, int>{
    '1 hour': 60 * 60,
    '6 hours': 6 * 60 * 60,
    '24 hours': 24 * 60 * 60,
    '3 days': 3 * 24 * 60 * 60,
  };

  @override
  void dispose() {
    _item.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final session = await ref.read(walletControllerProvider.notifier).require();
    if (session == null || !mounted) return;

    final lamports = Money.solToLamports(_price.text);
    if (lamports == null) return;

    final offer = EscrowOffer(
      seller: session.address.value,
      lamports: lamports,
      nonce: EscrowOffer.freshNonce(),
      item: _item.text.trim(),
      cluster: ref.read(clusterProvider).id,
      timeoutSeconds: _timeoutSeconds,
    );

    await HapticFeedback.mediumImpact();
    if (!mounted) return;

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OfferQrScreen(offer: offer)));
  }

  @override
  Widget build(BuildContext context) {
    final wallet = ref.watch(walletControllerProvider);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Create a listing')),
      extendBodyBehindAppBar: true,
      body: CircuitBackdrop(
        glowColor: Palette.violet,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
            children: [
              Text('THE TRADE', style: text.labelSmall),
              Gap.sm,
              Text('What are you selling?', style: text.headlineMedium),
              Gap.lg,

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _item,
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: 'Item',
                        hintText: 'Pixel 8 Pro, 256GB',
                        counterText: '',
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Give the buyer something to recognise.'
                          : null,
                    ),
                    Gap.md,
                    TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,9}'),
                        ),
                      ],
                      style: AppType.mono(size: 16, color: Palette.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        hintText: '0.5',
                        suffixText: 'SOL',
                      ),
                      validator: (value) =>
                          Money.solToLamports(value ?? '') == null
                          ? 'Enter an amount greater than zero.'
                          : null,
                    ),
                  ],
                ),
              ),

              Gap.lg,
              Text('REFUND WINDOW', style: text.labelSmall),
              Gap.sm,
              Text(
                'The buyer can call off the trade during this window. After '
                'it, you can claim the funds even if they never confirm.',
                style: text.bodyMedium,
              ),
              Gap.md,
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _timeoutChoices.entries.map((choice) {
                  final selected = _timeoutSeconds == choice.value;
                  return ChoiceChip(
                    label: Text(choice.key),
                    selected: selected,
                    onSelected: (_) =>
                        setState(() => _timeoutSeconds = choice.value),
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      color: selected ? Palette.void_ : Palette.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    backgroundColor: Palette.surfaceRaised,
                    selectedColor: Palette.cyan,
                    side: BorderSide(
                      color: selected ? Palette.cyan : Palette.hairline,
                    ),
                  );
                }).toList(),
              ),

              Gap.lg,
              GlassPanel(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Palette.cyan,
                    ),
                    Gap.md,
                    Expanded(
                      child: Text(
                        wallet.isConnected
                            ? 'The buyer funds an account only the program can '
                                  'open. You get paid the moment they confirm '
                                  'receipt.'
                            : 'Connect a wallet first — the QR code has to '
                                  'carry the address that will be paid.',
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),

              if (wallet.error != null) ...[
                Gap.md,
                _ErrorNote(message: wallet.error!),
              ],

              Gap.xl,
              GradientButton(
                label: wallet.isConnected
                    ? 'Generate QR code'
                    : 'Connect wallet & continue',
                icon: Icons.qr_code_2_rounded,
                busy: wallet.connecting,
                onPressed: _generate,
              ).animate().fadeIn(delay: 150.ms),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
            size: 17,
            color: Palette.danger,
          ),
          Gap.md,
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Palette.danger, fontSize: 13),
            ),
          ),
        ],
      ),
    ).animate().shake(hz: 3, offset: const Offset(2, 0)).fadeIn();
  }
}

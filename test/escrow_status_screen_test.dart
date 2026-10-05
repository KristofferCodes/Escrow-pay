import 'dart:typed_data';

import 'package:escrow_pay/core/escrow.dart';
import 'package:escrow_pay/core/qr_payload.dart';
import 'package:escrow_pay/features/status/escrow_status_screen.dart';
import 'package:escrow_pay/solana/escrow_controller.dart';
import 'package:escrow_pay/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana_kit/solana_kit.dart';

/// Serves a fixed [EscrowView] so the screen can be rendered in every state
/// without a wallet or a cluster.
class _StubController extends EscrowController {
  _StubController(this._view);
  final EscrowView _view;

  @override
  EscrowView build() => _view;
}

void main() {
  const seller = 'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS';
  const buyer = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
  const escrowAddress = Address('11111111111111111111111111111112');

  setUp(() {
    // The screen is a ListView, which only builds what fits. On the default
    // 800x600 surface the action row never renders, so give the tests a
    // viewport tall enough to hold the whole screen at once.
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 1.0;
    view.physicalSize = const Size(420, 1800);
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  const offer = EscrowOffer(
    seller: seller,
    lamports: 1500000000,
    nonce: 7,
    item: 'Pixel 8 Pro',
    cluster: 'devnet',
  );

  Escrow escrowIn(EscrowState state, {DateTime? deadline}) => Escrow(
    address: escrowAddress.value,
    seller: seller,
    buyer: buyer,
    amount: 1500000000,
    state: state,
    createdAt: DateTime.utc(2026, 9, 24, 12),
    deadline: deadline ?? DateTime.now().add(const Duration(hours: 24)),
    releaseHash: Uint8List(32),
    nonce: 7,
    bump: 254,
  );

  Future<void> pump(WidgetTester tester, EscrowView view) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          escrowControllerProvider.overrideWith(() => _StubController(view)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const EscrowStatusScreen(),
        ),
      ),
    );
    // The ring and backdrop animate forever, so settle a fixed span instead of
    // waiting for quiescence.
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('states the inspection window before anything is signed', (
    tester,
  ) async {
    // The seller picks this window, so the buyer has to be able to see a
    // hostile one and walk away rather than discover it after paying.
    await pump(tester, const EscrowView(offer: offer));

    expect(find.textContaining('24 hours to inspect'), findsOneWidget);
    expect(find.textContaining('seller can claim'), findsOneWidget);
  });

  testWidgets('tells the buyer to inspect once funded', (tester) async {
    await pump(
      tester,
      EscrowView(offer: offer, escrow: escrowIn(EscrowState.funded)),
    );

    expect(find.textContaining('Ready for handover'), findsOneWidget);
    expect(find.textContaining('left to refund instead'), findsOneWidget);
  });

  testWidgets('says the window has closed once it has', (tester) async {
    await pump(
      tester,
      EscrowView(
        offer: offer,
        escrow: escrowIn(
          EscrowState.funded,
          deadline: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      ),
    );

    expect(find.textContaining('refund window has closed'), findsOneWidget);
    expect(find.textContaining('Ready for handover'), findsNothing);
  });

  testWidgets('drops the window note once settled', (tester) async {
    await pump(
      tester,
      EscrowView(offer: offer, escrow: escrowIn(EscrowState.released)),
    );

    expect(find.textContaining('inspect'), findsNothing);
    expect(find.textContaining('Ready for handover'), findsNothing);
  });

  testWidgets('offers only funding before the escrow exists onchain', (
    tester,
  ) async {
    await pump(tester, const EscrowView(offer: offer));

    expect(find.text('Fund the escrow'), findsOneWidget);
    expect(find.text('Confirm receipt & release'), findsNothing);
    expect(find.text('Pixel 8 Pro'), findsOneWidget);
    // Amount comes from the scanned offer until the chain has an answer.
    expect(find.text('1.5'), findsOneWidget);
    expect(find.text('1.5 SOL'), findsOneWidget);
  });

  testWidgets('offers release and refund once funded', (tester) async {
    await pump(
      tester,
      EscrowView(offer: offer, escrow: escrowIn(EscrowState.funded)),
    );

    expect(find.text('In escrow'), findsOneWidget);
    expect(find.text('Confirm receipt & release'), findsOneWidget);
    expect(find.text('Something is wrong — refund me'), findsOneWidget);
    expect(find.text('Fund the escrow'), findsNothing);
  });

  testWidgets('a released escrow offers no further action', (tester) async {
    await pump(
      tester,
      EscrowView(offer: offer, escrow: escrowIn(EscrowState.released)),
    );

    expect(find.text('Released to seller'), findsOneWidget);
    expect(find.text('Settled onchain'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Confirm receipt & release'), findsNothing);
    expect(find.text('Something is wrong — refund me'), findsNothing);
  });

  testWidgets('a refunded escrow reads as refunded, not released', (
    tester,
  ) async {
    await pump(
      tester,
      EscrowView(offer: offer, escrow: escrowIn(EscrowState.refunded)),
    );

    expect(find.text('Refunded to buyer'), findsOneWidget);
    expect(find.text('Refunded onchain'), findsOneWidget);
    expect(find.text('Settled onchain'), findsNothing);
  });

  testWidgets('shows a skeleton while the first read is in flight', (
    tester,
  ) async {
    await pump(tester, const EscrowView(loading: true));

    expect(find.text('Fund the escrow'), findsNothing);
    expect(find.text('Awaiting funds'), findsNothing);
  });

  testWidgets('surfaces an error without hiding the escrow', (tester) async {
    await pump(
      tester,
      EscrowView(
        offer: offer,
        escrow: escrowIn(EscrowState.funded),
        error: 'Could not reach the cluster. Check the connection and retry.',
      ),
    );

    expect(
      find.text('Could not reach the cluster. Check the connection and retry.'),
      findsOneWidget,
    );
    expect(find.text('In escrow'), findsOneWidget);
  });

  testWidgets('disables actions while a wallet round trip is in flight', (
    tester,
  ) async {
    await pump(
      tester,
      EscrowView(
        offer: offer,
        escrow: escrowIn(EscrowState.funded),
        busy: true,
      ),
    );

    final view = EscrowView(
      offer: offer,
      escrow: escrowIn(EscrowState.funded),
      busy: true,
    );
    expect(view.canConfirm, isFalse);
    expect(view.canRefund, isFalse);
  });
}

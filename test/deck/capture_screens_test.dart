// Renders real app screens to PNGs for the pitch deck.
//
// Not a correctness test — it exists so deck images come from the actual
// widget tree rather than a mockup that drifts from what ships.
//
//   flutter test test/deck/capture_screens_test.dart --update-goldens
//
// Images land in test/deck/goldens/.
@Tags(['deck'])
library;

import 'dart:io';

import 'package:escrow_pay/core/escrow.dart';
import 'package:escrow_pay/core/listing.dart';
import 'package:escrow_pay/core/qr_payload.dart';
import 'package:escrow_pay/core/release_code.dart';
import 'package:escrow_pay/features/create_listing/offer_qr_screen.dart';
import 'package:escrow_pay/features/history/history_screen.dart';
import 'package:escrow_pay/features/home/home_screen.dart';
import 'package:escrow_pay/features/listings/listings_screen.dart';
import 'package:escrow_pay/features/status/escrow_status_screen.dart';
import 'package:escrow_pay/features/status/release_code_sheet.dart';
import 'package:escrow_pay/solana/escrow_controller.dart';
import 'package:escrow_pay/solana/history_controller.dart';
import 'package:escrow_pay/solana/listings_controller.dart';
import 'package:escrow_pay/solana/wallet.dart';
import 'package:escrow_pay/solana/wallet_controller.dart';
import 'package:escrow_pay/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana_kit/solana_kit.dart';

const _seller = 'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS';
const _buyer = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
const _escrowAddr = '8soL4N6X6So1c1hN5WpSX5PMNmcHrpA6tnt1LNTPH6dm';

/// Fixed so the rendered QR is identical run to run. A generated secret
/// would change the image every time and make the golden meaningless.
final _deckCode = ReleaseCode(
  Uint8List.fromList(List.generate(32, (i) => (i * 7 + 11) % 256)),
);

const _offer = EscrowOffer(
  seller: _seller,
  lamports: 450000000,
  nonce: 1790435254583,
  item: 'Pixel 8 Pro, 256GB',
  cluster: 'devnet',
);

Escrow _escrow(
  EscrowState state, {
  Duration left = const Duration(hours: 23),
}) => Escrow(
  address: _escrowAddr,
  seller: _seller,
  buyer: _buyer,
  amount: 450000000,
  state: state,
  createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
  deadline: DateTime.now().add(left),
  releaseHash: Uint8List.fromList(List.filled(32, 7)),
  nonce: 1790435254583,
  bump: 254,
);

class _StubEscrow extends EscrowController {
  _StubEscrow(this._view);
  final EscrowView _view;
  @override
  EscrowView build() => _view;
}

class _StubWallet extends WalletController {
  _StubWallet({this.connected = true});
  final bool connected;
  @override
  WalletState build() => connected
      ? const WalletState(
          session: WalletSession(address: Address(_buyer), authToken: 'stub'),
        )
      : const WalletState();
}

class _StubHistory extends HistoryController {
  _StubHistory(this._items);
  final List<Escrow> _items;
  @override
  Future<List<Escrow>> build() async => _items;
}

class _StubListings extends ListingsController {
  _StubListings(this._state);
  final ListingsState _state;
  @override
  ListingsState build() => _state;
}

void main() {
  setUpAll(() async {
    // flutter_test renders every glyph as a filled box unless real fonts are
    // registered — declaring them in pubspec is not enough here. Loading the
    // bundled TTFs directly is what makes these shots show the app's own
    // type rather than a wall of rectangles.
    TestWidgetsFlutterBinding.ensureInitialized();

    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final file in files) {
        final bytes = File('assets/fonts/$file').readAsBytesSync();
        loader.addFont(
          Future.value(ByteData.sublistView(Uint8List.fromList(bytes))),
        );
      }
      await loader.load();
    }

    await load('Space Grotesk', [
      'SpaceGrotesk-Regular.ttf',
      'SpaceGrotesk-SemiBold.ttf',
      'SpaceGrotesk-Bold.ttf',
    ]);
    await load('JetBrains Mono', [
      'JetBrainsMono-Regular.ttf',
      'JetBrainsMono-Medium.ttf',
      'JetBrainsMono-Bold.ttf',
    ]);

    // Icons are a font too, and without it every icon is a box.
    const iconFont =
        '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf';
    if (File(iconFont).existsSync()) {
      final loader = FontLoader('MaterialIcons');
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            Uint8List.fromList(File(iconFont).readAsBytesSync()),
          ),
        ),
      );
      await loader.load();
    }
  });

  /// Takes the whole ProviderScope rather than a list of overrides, because
  /// flutter_riverpod does not export the Override type.
  Future<void> capture(
    WidgetTester tester,
    String name,
    Widget app, {
    Size size = const Size(400, 860),
  }) async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 2.0;
    view.physicalSize = size * 2.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(app);
    // Long enough for fonts to land and entry animations to settle.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('home', (tester) async {
    await capture(
      tester,
      '01-home',
      ProviderScope(
        overrides: [
          walletControllerProvider.overrideWith(_StubWallet.new),
          listingsControllerProvider.overrideWith(
            () => _StubListings(
              ListingsState(
                listings: [
                  WatchedListing(
                    listing: Listing(offer: _offer, createdAt: DateTime.now()),
                    escrow: _escrow(EscrowState.funded),
                  ),
                ],
              ),
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: const HomeScreen(),
        ),
      ),
    );
  });

  testWidgets('offer qr', (tester) async {
    await capture(
      tester,
      '02-listing-qr',
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: const OfferQrScreen(offer: _offer),
        ),
      ),
    );
  });

  testWidgets('status funded', (tester) async {
    await capture(
      tester,
      '03-escrow-funded',
      ProviderScope(
        overrides: [
          walletControllerProvider.overrideWith(_StubWallet.new),
          escrowControllerProvider.overrideWith(
            () => _StubEscrow(
              EscrowView(
                offer: _offer,
                address: const Address(_escrowAddr),
                escrow: _escrow(EscrowState.funded),
                releaseCode: _deckCode,
              ),
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: const EscrowStatusScreen(),
        ),
      ),
    );
  });

  testWidgets('status released', (tester) async {
    await capture(
      tester,
      '04-escrow-released',
      ProviderScope(
        overrides: [
          walletControllerProvider.overrideWith(_StubWallet.new),
          escrowControllerProvider.overrideWith(
            () => _StubEscrow(
              EscrowView(
                offer: _offer,
                address: const Address(_escrowAddr),
                escrow: _escrow(EscrowState.released),
                lastSignature:
                    '4zrhnvsqQNG5ZsLH9CE2WfxNqDca32ibcJmHRRLUW9ysEQRdfK1VTN3',
              ),
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: const EscrowStatusScreen(),
        ),
      ),
    );
  });

  testWidgets('release code', (tester) async {
    await capture(
      tester,
      '05-release-code',
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: Scaffold(
            backgroundColor: const Color(0xFF13131F),
            body: ReleaseCodeSheet(
              payload: ReleasePayload(
                escrow: _escrowAddr,
                code: _deckCode,
                cluster: 'devnet',
              ),
              amount: 450000000,
              seller: _seller,
            ),
          ),
        ),
      ),
      size: const Size(400, 720),
    );
  });

  testWidgets('listings', (tester) async {
    await capture(
      tester,
      '06-listings',
      _scope(const ListingsScreen(), [
        walletControllerProvider.overrideWith(_StubWallet.new),
        listingsControllerProvider.overrideWith(
          () => _StubListings(
            ListingsState(
              listings: [
                WatchedListing(
                  listing: Listing(offer: _offer, createdAt: DateTime.now()),
                  escrow: _escrow(EscrowState.funded),
                ),
                WatchedListing(
                  listing: Listing(
                    offer: const EscrowOffer(
                      seller: _seller,
                      lamports: 120000000,
                      nonce: 1790435254111,
                      item: 'Mechanical keyboard',
                      cluster: 'devnet',
                    ),
                    createdAt: DateTime.now().subtract(
                      const Duration(hours: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  });

  testWidgets('history', (tester) async {
    await capture(
      tester,
      '07-trades',
      _scope(const HistoryScreen(), [
        walletControllerProvider.overrideWith(_StubWallet.new),
        historyControllerProvider.overrideWith(
          () => _StubHistory([
            _escrow(EscrowState.released),
            _escrow(EscrowState.funded),
            _escrow(EscrowState.refunded),
          ]),
        ),
      ]),
    );
  });
}

/// Builds the app around a screen with the given provider overrides.
Widget _scope(Widget home, List<Object> overrides) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark(),
    home: home,
  ),
);

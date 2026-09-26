// Renders a seller QR code without needing a second phone.
//
// The seller side of Escrow Pay never signs anything — it reads a wallet
// address, puts it in a QR and stops. So testing the whole escrow flow needs
// exactly one Android device: this puts the seller's QR on your laptop screen
// and the phone scans it.
//
// The offer is built with the app's own `EscrowOffer.encode`, so a test QR
// cannot drift from what the scanner expects.
//
//   dart run tool/make_test_offer.dart <seller-address> [sol] [item]
//
// Writes build/test-offer.html — open it and make the browser window big.

import 'dart:io';

import 'package:escrow_pay/core/money.dart';
import 'package:escrow_pay/core/qr_payload.dart';
import 'package:qr/qr.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/make_test_offer.dart '
      '<seller-address> [sol] [item]',
    );
    stderr.writeln();
    stderr.writeln('Generate a throwaway seller address first:');
    stderr.writeln('  solana-keygen new --no-bip39-passphrase --silent \\');
    stderr.writeln('      --outfile .seller-test.json');
    stderr.writeln('  solana address -k .seller-test.json');
    exit(64);
  }

  final seller = args[0];
  final sol = args.length > 1 ? args[1] : '0.05';
  final item = args.length > 2 ? args.sublist(2).join(' ') : 'Test item';

  final lamports = Money.solToLamports(sol);
  if (lamports == null) {
    stderr.writeln('Not a valid SOL amount: $sol');
    exit(65);
  }

  final offer = EscrowOffer(
    seller: seller,
    lamports: lamports,
    nonce: EscrowOffer.freshNonce(),
    item: item,
    // Must match Cluster.active in the app, or the scanner rejects the code.
    cluster: 'devnet',
  );

  final uri = offer.encode();
  final out = File('build/test-offer.html')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(_page(offer, uri));

  stdout
    ..writeln('seller:  $seller')
    ..writeln('amount:  ${Money.sol(lamports)}')
    ..writeln('item:    $item')
    ..writeln('nonce:   ${offer.nonce}')
    ..writeln('')
    ..writeln('uri:     $uri')
    ..writeln('')
    ..writeln('wrote ${out.path} — open it and scan from the device:')
    ..writeln('  open ${out.path}');
}

/// Draws the QR as SVG rects. Avoids needing any image library on a machine
/// that has none.
String _page(EscrowOffer offer, String uri) {
  final qr = QrCode.fromData(
    data: uri,
    // High correction: a phone camera pointed at a laptop screen deals with
    // glare and moire, and the extra redundancy makes the lock-on quicker.
    errorCorrectLevel: QrErrorCorrectLevel.H,
  );
  final image = QrImage(qr);
  final count = image.moduleCount;

  const quiet = 4; // modules; the spec's minimum silent zone
  final span = count + quiet * 2;

  final rects = StringBuffer();
  for (var row = 0; row < count; row++) {
    for (var col = 0; col < count; col++) {
      if (!image.isDark(row, col)) continue;
      // Slight overlap closes hairline seams between adjacent modules when
      // the browser scales the SVG up.
      rects.write(
        '<rect x="${col + quiet}" y="${row + quiet}" '
        'width="1.02" height="1.02"/>',
      );
    }
  }

  return '''<!doctype html>
<meta charset="utf-8">
<title>Escrow Pay — test offer</title>
<style>
  body { margin:0; min-height:100vh; display:grid; place-items:center;
         background:#0A0A12; color:#F4F4F8;
         font:14px/1.5 ui-sans-serif, system-ui, sans-serif; padding:24px; }
  .card { text-align:center; max-width:min(92vw, 560px); }
  .qr { background:#fff; padding:20px; border-radius:22px; display:inline-block;
        box-shadow:0 0 60px -10px rgba(34,211,238,.45); }
  svg { display:block; width:min(70vw, 380px); height:auto; }
  h1 { font-size:20px; margin:24px 0 4px; letter-spacing:-.3px; }
  p  { margin:4px 0; color:#A1A1B5; }
  code { font:12px ui-monospace, monospace; color:#22D3EE;
         word-break:break-all; }
  .amt { font:700 34px ui-monospace, monospace; letter-spacing:-1px;
         margin:16px 0 0; color:#F4F4F8; }
</style>
<div class="card">
  <div class="qr">
    <svg viewBox="0 0 $span $span" shape-rendering="crispEdges">
      <rect width="$span" height="$span" fill="#fff"/>
      <g fill="#0A0A12">$rects</g>
    </svg>
  </div>
  <p class="amt">${Money.sol(offer.lamports)}</p>
  <h1>${_escape(offer.item)}</h1>
  <p>seller <code>${_escape(offer.seller)}</code></p>
  <p>nonce ${offer.nonce} · ${offer.cluster}</p>
</div>
''';
}

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

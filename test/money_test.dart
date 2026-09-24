import 'package:escrow_pay/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('solToLamports', () {
    test('converts whole and fractional amounts', () {
      expect(Money.solToLamports('1'), 1000000000);
      expect(Money.solToLamports('0.5'), 500000000);
      expect(Money.solToLamports('0.000000001'), 1);
    });

    test('rounds rather than truncating', () {
      // 0.1 * 1e9 is 99999999.99999999 in binary floating point; truncating
      // here would silently underpay the seller by a lamport.
      expect(Money.solToLamports('0.1'), 100000000);
      expect(Money.solToLamports('0.3'), 300000000);
      expect(Money.solToLamports('2.7'), 2700000000);
    });

    test('tolerates padding and thousands separators', () {
      expect(Money.solToLamports('  1.5  '), 1500000000);
      expect(Money.solToLamports('1,000'), 1000000000000);
    });

    test('rejects anything that is not a positive amount', () {
      expect(Money.solToLamports(''), isNull);
      expect(Money.solToLamports('0'), isNull);
      expect(Money.solToLamports('-1'), isNull);
      expect(Money.solToLamports('abc'), isNull);
      // Rounds to zero lamports, so there is nothing to escrow.
      expect(Money.solToLamports('0.0000000001'), isNull);
    });
  });

  group('solLabel', () {
    test('trims trailing zeros but keeps the leading digit', () {
      expect(Money.solLabel(1000000000), '1');
      expect(Money.solLabel(1500000000), '1.5');
      expect(Money.solLabel(1000000), '0.001');
      expect(Money.solLabel(1), '0.000000001');
      expect(Money.solLabel(0), '0');
    });

    test('round trips through solToLamports', () {
      for (final lamports in [1, 1000, 100000000, 1500000000, 42]) {
        expect(Money.solToLamports(Money.solLabel(lamports)), lamports);
      }
    });

    test('appends the ticker', () {
      expect(Money.sol(2500000000), '2.5 SOL');
    });
  });

  group('shortAddress', () {
    test('keeps both ends so it can be checked against a wallet', () {
      expect(
        Money.shortAddress('Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS'),
        'Fg6P…sLnS',
      );
    });

    test('leaves short strings alone', () {
      expect(Money.shortAddress('abc'), 'abc');
    });
  });
}

import 'package:escrow_pay/solana/history_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HistoryUnavailable.from', () {
    test('explains the Alchemy free-tier refusal in plain words', () {
      // The exact shape the user hit. Alchemy answers HTTP 400 and puts the
      // real reason in the JSON body, which the transport never parses — so
      // this opaque string was all the screen had to show.
      final failure = HistoryUnavailable.from(
        'SolanaError: solanaError#81000002: HTTP error (400): Bad Request',
      );

      expect(failure.message, isNot(contains('solanaError')));
      expect(failure.message, isNot(contains('81000002')));
      expect(failure.message, contains('getProgramAccounts'));
      // The reassurance matters: nothing is lost, only this list is broken.
      expect(failure.message, contains('safe onchain'));
    });

    test('names rate limiting rather than blaming the connection', () {
      final failure = HistoryUnavailable.from(
        'HTTP error (429): Too Many Requests',
      );
      expect(failure.message, contains('rate limiting'));
      expect(failure.message, contains('refresh'));
    });

    test('distinguishes an unreachable cluster', () {
      final failure = HistoryUnavailable.from(
        'ClientException: Connection closed before full header was received',
      );
      expect(failure.message, contains('Could not reach the cluster'));
    });

    test(
      'passes anything unrecognised through rather than inventing a cause',
      () {
        final failure = HistoryUnavailable.from('something entirely new');
        expect(failure.message, 'something entirely new');
      },
    );

    test('reads as its message', () {
      expect('${const HistoryUnavailable('plain words')}', 'plain words');
    });
  });
}

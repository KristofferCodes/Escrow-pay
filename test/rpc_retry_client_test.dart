import 'dart:async';
import 'dart:convert';

import 'package:escrow_pay/solana/rpc_retry_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// Answers with a scripted sequence of statuses and records what it saw.
class _ScriptedClient extends http.BaseClient {
  _ScriptedClient(this.statuses, {this.headers = const {}});

  final List<int> statuses;
  final Map<String, String> headers;
  final List<String> bodies = [];
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    bodies.add(utf8.decode(await request.finalize().toBytes()));
    final status = statuses[calls.clamp(0, statuses.length - 1)];
    calls++;
    return http.StreamedResponse(
      Stream.value(utf8.encode('{"jsonrpc":"2.0","result":$status}')),
      status,
      headers: headers,
    );
  }
}

class _FailingClient extends http.BaseClient {
  _FailingClient(this.failures);
  final int failures;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    calls++;
    if (calls <= failures) {
      throw http.ClientException('connection closed', request.url);
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  }
}

void main() {
  // Keep the backoff short so the suite stays fast; the timing policy itself
  // is covered by the Retry-After test below.
  RpcRetryClient build(http.Client inner, {int attempts = 5}) => RpcRetryClient(
    inner: inner,
    maxAttempts: attempts,
    initialBackoff: const Duration(milliseconds: 1),
    maxBackoff: const Duration(milliseconds: 5),
  );

  Future<http.StreamedResponse> post(RpcRetryClient client) => client.send(
    http.Request('POST', Uri.parse('https://rpc.example/v2/key'))
      ..body = '{"method":"getAccountInfo"}',
  );

  test('a throttled call is retried and eventually succeeds', () async {
    final inner = _ScriptedClient([429, 429, 200]);
    final response = await post(build(inner));

    expect(response.statusCode, 200);
    expect(inner.calls, 3);
  });

  test('the body is resent intact on every retry', () async {
    // The request body is a one-shot stream; without buffering it, retry two
    // would post nothing and the node would reject it.
    final inner = _ScriptedClient([429, 429, 200]);
    await post(build(inner));

    expect(inner.bodies, hasLength(3));
    expect(inner.bodies.toSet(), {'{"method":"getAccountInfo"}'});
  });

  test('gives up after maxAttempts and returns the last response', () async {
    final inner = _ScriptedClient([429]);
    final response = await post(build(inner, attempts: 3));

    expect(response.statusCode, 429);
    expect(inner.calls, 3);
  });

  test('retries the 5xx codes that mean the node could not answer', () async {
    for (final status in [500, 502, 503, 504]) {
      final inner = _ScriptedClient([status, 200]);
      final response = await post(build(inner));

      expect(response.statusCode, 200, reason: 'after $status');
      expect(inner.calls, 2, reason: 'after $status');
    }
  });

  test('does not retry a rejected request', () async {
    // 400 and 401 mean the request or key is wrong. Retrying just multiplies
    // the failure.
    for (final status in [400, 401, 403, 404]) {
      final inner = _ScriptedClient([status, 200]);
      final response = await post(build(inner));

      expect(response.statusCode, status);
      expect(inner.calls, 1, reason: 'should not retry $status');
    }
  });

  test('honours a Retry-After header in seconds', () async {
    final inner = _ScriptedClient([429, 200], headers: {'retry-after': '1'});
    final client = RpcRetryClient(
      inner: inner,
      maxAttempts: 3,
      initialBackoff: const Duration(milliseconds: 1),
      // Retry-After of 1s is clamped to this, proving the header was read and
      // that a hostile value cannot stall the UI.
      maxBackoff: const Duration(milliseconds: 40),
    );

    final started = DateTime.now();
    final response = await post(client);
    final waited = DateTime.now().difference(started);

    expect(response.statusCode, 200);
    expect(waited, greaterThan(const Duration(milliseconds: 20)));
    expect(waited, lessThan(const Duration(milliseconds: 400)));
  });

  test('retries a dropped connection', () async {
    final inner = _FailingClient(2);
    final response = await post(build(inner));

    expect(response.statusCode, 200);
    expect(inner.calls, 3);
  });

  test('rethrows when the connection never recovers', () async {
    final inner = _FailingClient(99);

    await expectLater(
      post(build(inner, attempts: 3)),
      throwsA(isA<http.ClientException>()),
    );
    expect(inner.calls, 3);
  });
}

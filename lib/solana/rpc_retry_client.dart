import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show parseHttpDate;

/// An HTTP client that retries throttled and transient RPC failures.
///
/// Solana RPC endpoints answer 429 readily — the public ones under almost any
/// load, and paid ones once a plan's rate is exceeded. A single 429 surfacing
/// as "could not reach the cluster" mid-demo is a bad trade when waiting a few
/// hundred milliseconds would have worked.
///
/// Only idempotent failures are retried: 429, and the 5xx codes that mean the
/// node could not answer rather than that it rejected the request. The app's
/// own RPC traffic is reads — `getAccountInfo` and `getLatestBlockhash` —
/// because transactions are submitted by the wallet over MWA, not from here,
/// so a replayed request cannot double-spend anything.
class RpcRetryClient extends http.BaseClient {
  RpcRetryClient({
    http.Client? inner,
    this.maxAttempts = 5,
    this.initialBackoff = const Duration(milliseconds: 250),
    this.maxBackoff = const Duration(seconds: 8),
  }) : _inner = inner ?? http.Client();

  final http.Client _inner;

  /// Total tries, not retries. 5 spans roughly four seconds of backoff.
  final int maxAttempts;

  final Duration initialBackoff;

  /// Ceiling for a single wait, so a long `Retry-After` cannot stall the UI
  /// indefinitely.
  final Duration maxBackoff;

  static const _retryableStatuses = {
    429, // throttled
    500, // node failed to answer
    502,
    503,
    504,
  };

  final _random = Random();
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    // A streamed body can only be read once, so buffer it up front — every
    // retry needs to send the same bytes again.
    final body = await request.finalize().toBytes();

    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_closed) throw StateError('RpcRetryClient was closed');

      try {
        final response = await _inner.send(_copy(request, body));

        if (!_retryableStatuses.contains(response.statusCode) ||
            attempt == maxAttempts) {
          return response;
        }

        // Drain the body so the connection can be reused.
        await response.stream.drain<void>();
        await Future<void>.delayed(
          _backoff(attempt, retryAfter: response.headers['retry-after']),
        );
      } on http.ClientException catch (error) {
        // A dropped connection is worth one more go; a bad URL is not, but it
        // will fail the same way on the final attempt and be rethrown.
        lastError = error;
        if (attempt == maxAttempts) rethrow;
        await Future<void>.delayed(_backoff(attempt));
      }
    }

    throw lastError ?? StateError('RPC retries exhausted');
  }

  /// Exponential backoff with jitter. The jitter matters: without it, several
  /// calls throttled by the same burst retry in lockstep and throttle again.
  Duration _backoff(int attempt, {String? retryAfter}) {
    final server = _parseRetryAfter(retryAfter);
    if (server != null) {
      return server > maxBackoff ? maxBackoff : server;
    }

    final growth = initialBackoff * pow(2, attempt - 1).toDouble();
    final capped = growth > maxBackoff ? maxBackoff : growth;
    final jitter = _random.nextDouble() * 0.3 + 0.85; // 0.85x .. 1.15x
    return Duration(microseconds: (capped.inMicroseconds * jitter).round());
  }

  /// `Retry-After` is either seconds or an HTTP date. Honour it when the
  /// server bothered to send one.
  static Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;

    final seconds = int.tryParse(value.trim());
    if (seconds != null) {
      return seconds < 0 ? null : Duration(seconds: seconds);
    }

    try {
      final until = parseHttpDate(value);
      final delta = until.difference(DateTime.now().toUtc());
      return delta.isNegative ? null : delta;
    } on Object {
      return null;
    }
  }

  static http.Request _copy(http.BaseRequest original, List<int> body) {
    return http.Request(original.method, original.url)
      ..headers.addAll(original.headers)
      ..bodyBytes = body
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
  }

  @override
  void close() {
    _closed = true;
    _inner.close();
  }
}

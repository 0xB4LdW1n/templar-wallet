/// What a person reads when publishing an offer to the order book fails.
///
/// The engine tags every order-book refusal of `swap_publish` by the book's
/// HTTP status (`BOOK_RATE_LIMITED:`, `BOOK_DUPLICATE:`, …; templarlib
/// docs/API.md, `swap_publish`). The tag is the contract; the text after it
/// may change, so only the retry delay is read from it.
library;

import '../settings/test_server_switch.dart' show kTestServerSettingsPath;
import 'take_flow.dart' show swapError;

/// The engine's refusal of a publish, as a message with what to do next.
String swapPublishErrorText(Object error) {
  final raw = swapError(error);
  final colon = raw.indexOf(':');
  if (!raw.startsWith('BOOK_') || colon < 0) return raw;
  final tag = raw.substring(0, colon);
  final detail = raw.substring(colon + 1).trim();
  return switch (tag) {
    'BOOK_RATE_LIMITED' =>
      'The order book is limiting publishes: too many offers came from here. '
          'Try again ${_retryIn(detail) ?? 'in a few minutes'}.',
    'BOOK_CHAIN_UNREACHABLE' =>
      'The order book cannot check the chain right now, so the offer was not '
          'stored. Try again ${_retryIn(detail) ?? 'later'}.',
    'BOOK_DUPLICATE' =>
      'Already published: this offer is in the order book. Nothing to do.',
    'BOOK_PUBLISH_DISABLED' =>
      'This order book does not take public offers on this network. Share '
          'the proposal with the taker directly instead.',
    'BOOK_REJECTED' =>
      detail.isEmpty ? 'The order book refused the offer.' : detail,
    'BOOK_UNREACHABLE' =>
      '$detail Check the test server in $kTestServerSettingsPath, then try '
          'again.',
    'BOOK_UNAVAILABLE' => detail,
    _ => raw,
  };
}

/// "in 42 seconds" / "in 3 minutes", from the engine's "Try again in N
/// seconds"; null when the book gave no delay.
String? _retryIn(String detail) {
  final m = RegExp(r'Try again in (\d+) seconds?').firstMatch(detail);
  if (m == null) return null;
  final seconds = int.parse(m.group(1)!);
  if (seconds < 90) return 'in $seconds second${seconds == 1 ? '' : 's'}';
  final minutes = (seconds / 60).ceil();
  return 'in $minutes minutes';
}

/// A refusal of `test_server_faucet`, in plain words.
///
/// The engine tags each refusal (templarlib docs/API.md,
/// `test_server_faucet`); the app keys on the tag and keeps the faucet's own
/// reason after it, which is already written for people.
library;

enum FaucetErrorKind { unavailable, rateLimited, refused, unreachable, other }

class FaucetError {
  const FaucetError({
    required this.kind,
    required this.message,
    this.retryAfter,
  });

  final FaucetErrorKind kind;

  /// One or two sentences for the user, ending without a full stop.
  final String message;

  /// When to ask again (`FAUCET_RATE_LIMITED` with `Try again in N seconds`).
  final Duration? retryAfter;

  static final _retry = RegExp(r'Try again in (\d+) seconds?\.?');

  factory FaucetError.from(Object error) {
    final raw = error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('wallet-ffi: ', '')
        .trim();
    final colon = raw.indexOf(':');
    final tag = colon < 0 ? '' : raw.substring(0, colon);
    final detail = colon < 0 ? raw : raw.substring(colon + 1).trim();
    switch (tag) {
      case 'FAUCET_RATE_LIMITED':
        final m = _retry.firstMatch(detail);
        final seconds = m == null ? null : int.tryParse(m.group(1)!);
        final reason = _trim(detail.replaceAll(_retry, '').trim());
        final when = seconds == null
            ? 'Try again later'
            : 'Try again in ${_duration(seconds)}';
        return FaucetError(
          kind: FaucetErrorKind.rateLimited,
          message: reason.isEmpty
              ? 'The faucet\'s limit is reached. $when'
              : 'The faucet\'s limit is reached ($reason). $when',
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
      case 'FAUCET_UNAVAILABLE':
        return FaucetError(
          kind: FaucetErrorKind.unavailable,
          message: 'The faucet cannot pay this here: ${_trim(detail)}',
        );
      case 'FAUCET_REFUSED':
        return FaucetError(
          kind: FaucetErrorKind.refused,
          message: 'The faucet refused: ${_trim(detail)}',
        );
      case 'FAUCET_UNREACHABLE':
        return FaucetError(
          kind: FaucetErrorKind.unreachable,
          message:
              'The test server\'s faucet did not answer. Check that the '
              'test server is running, then try again',
        );
      default:
        return FaucetError(kind: FaucetErrorKind.other, message: _trim(raw));
    }
  }

  /// "90 seconds", "2 minutes", "1 hour".
  static String _duration(int seconds) {
    if (seconds < 120) return '$seconds second${seconds == 1 ? '' : 's'}';
    final minutes = (seconds / 60).ceil();
    if (minutes < 120) return '$minutes minutes';
    final hours = (minutes / 60).ceil();
    return '$hours hour${hours == 1 ? '' : 's'}';
  }

  /// Drops a closing full stop: the message is a status line.
  static String _trim(String text) {
    final t = text.trim();
    return t.endsWith('.') ? t.substring(0, t.length - 1) : t;
  }
}

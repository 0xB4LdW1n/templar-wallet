/// The order book's admin dashboard, offered only where it makes sense.
///
/// The book's base URL comes from the engine (`active.orderbook.origin`):
/// the joined test server's book, an environment override, or the local
/// default. Its admin dashboard is a separate, password-protected page at
/// the origin. The app links to it only when the book runs on this machine
/// (a loopback origin) — a tester's local lab; a remote book's admin is its
/// operator's, not the user's.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';

/// The admin page of the book in use, or null when the app should not offer
/// it (no answer from the engine yet, or a book on another machine).
///
/// A joined test server on this machine has ONE control dashboard for the
/// whole lab: its order book page is `<test server>/admin#liquidex`. Without
/// a lab (or with a lab elsewhere) the rule stays: the book's own origin,
/// only when that book runs on this machine.
Uri? orderBookAdminUri(AppState state) {
  final server = state.testServer;
  final base = server?.profile?.baseUrl ?? '';
  if ((server?.configured ?? false) && _isLoopback(base)) {
    final trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return Uri.tryParse('$trimmed/admin#liquidex');
  }
  final book = server?.active.orderbook;
  if (book == null || !book.isLoopback) return null;
  return Uri.tryParse(book.origin.url);
}

bool _isLoopback(String url) {
  final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
  return host == '127.0.0.1' ||
      host == 'localhost' ||
      host == '::1' ||
      host == '[::1]';
}

Future<void> openOrderBookAdmin(BuildContext context, Uri uri) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open the order book admin at $uri')),
    );
  }
}

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
Uri? orderBookAdminUri(AppState state) {
  final book = state.testServer?.active.orderbook;
  if (book == null || !book.isLoopback) return null;
  return Uri.tryParse(book.origin.url);
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

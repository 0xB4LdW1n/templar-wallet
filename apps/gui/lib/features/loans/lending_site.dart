/// The joined test server's Templar Protocol (lending) site.
///
/// A lab publishes it as `protocol_url`; the engine reports it as
/// `active.protocol` only while the active network is that lab's own
/// regtest. The app only opens it in the browser: connecting still happens
/// from the site's own "Connect Templar Wallet", through its templar:// link.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';

/// The lab's lending site now, or null (no lab, or not on its regtest).
Uri? labLendingSite(AppState state) {
  final url = state.testServer?.protocolUrl;
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
    return null;
  }
  return uri;
}

/// The button's words, the same everywhere.
const String kOpenLendingSite = 'Open the test server\'s lending site';

Future<void> openLabLendingSite(BuildContext context, Uri uri) async {
  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not open the lending site at $uri')),
    );
  }
}

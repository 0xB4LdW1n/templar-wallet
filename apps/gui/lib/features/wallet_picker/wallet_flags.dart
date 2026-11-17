// The one-line description under a wallet's name: how its keys are held,
// which chains it carries, and which key it actually is. Both questions get
// asked before a wallet is opened, and a wrong guess costs a wallet open, a
// device unlock and a trip back.
//
// One sentence of facts, never a row of coloured pills.

import 'package:flutter/material.dart';

import '../../theme/app_scheme.dart';
import '../../theme/app_typography.dart';
import 'models/wallet_summary.dart';

class WalletFlags extends StatelessWidget {
  const WalletFlags({
    super.key,
    required this.wallet,
    this.compact = false,
    this.stacked = false,
    this.color,
  });

  final WalletSummary wallet;

  /// Drop to the single most identifying fact — for tight rows.
  final bool compact;

  /// Break the fingerprint onto its own second line, for a narrow slot: on
  /// one line, "Software · BTC + Liquid · f0b68896" ellipses the fingerprint
  /// down to "f…" — the one fact on the line you cannot guess.
  final bool stacked;

  /// Overrides the text colour.
  final Color? color;

  /// The facts, in the order they are worth reading: what holds the keys,
  /// which chains are on it, and which key it is.
  static List<String> partsOf(WalletSummary w, {bool compact = false}) {
    final parts = <String>[];
    final kind = w.keyOriginLabel;
    if (kind != null) parts.add(kind);
    if (!compact) parts.add(w.networksLabel);
    return parts;
  }

  /// The picker's caption line, in words rather than tickers:
  /// "Single key · software · Bitcoin + Liquid", "2-of-3 multisig · Bitcoin",
  /// "Watch-only · Bitcoin". Built only from the facts the summary carries;
  /// the fingerprint is left out because the row prints it on its own.
  static String describe(WalletSummary w) {
    final chains = w.bitcoinEnabled && w.liquidEnabled
        ? 'Bitcoin + Liquid'
        : w.liquidEnabled
        ? 'Liquid'
        : 'Bitcoin';
    return '${kindLabel(w)} · $chains';
  }

  /// How the wallet's keys are held, in words: "Single key · software",
  /// "2-of-3 multisig", "Watch-only". The first half of [describe], for a
  /// row that prints the chains in a column of their own.
  static String kindLabel(WalletSummary w) {
    if (w.isAirgapWallet) return 'Air-gapped signer';
    if (w.isViewOnlyWallet) return 'Watch-only';
    if (w.type == WalletType.multisig) {
      final t = w.thresholdLabel;
      return t == null ? 'Multisig' : '$t multisig';
    }
    if (w.isHardwareWallet) {
      final device = w.keyOriginLabel ?? 'USB device';
      return 'Single key · $device';
    }
    if (w.type == WalletType.watchOnly || w.isWatchOnly) return 'Watch-only';
    return 'Single key · software';
  }

  /// Icon for the key-origin fact — the one glyph worth keeping.
  static IconData kindIcon(WalletSummary w) {
    if (w.isAirgapWallet) return Icons.qr_code_2_outlined;
    if (w.isViewOnlyWallet) return Icons.visibility_outlined;
    if (w.type == WalletType.multisig) return Icons.groups_outlined;
    if (w.isHardwareWallet) return Icons.usb_outlined;
    // A summary with no type label (older registry rows) still says it is
    // watch-only through its type; the caption already reads "Watch-only".
    if (w.type == WalletType.watchOnly) return Icons.visibility_outlined;
    return Icons.vpn_key_outlined;
  }

  /// The same mapping, from the display label the shell carries.
  ///
  /// Inside an open wallet there is no [WalletSummary] — AppState keeps only
  /// the type label ("Multisig 2-of-3", "Air-gap watch-only", …) — but the
  /// sidebar has to draw the same mark the picker drew, so it resolves the
  /// icon from that string. Air-gap is tested first: "Air-gap watch-only"
  /// contains "watch-only" and would otherwise match the wrong branch.
  static IconData kindIconForLabel(String? label) {
    final t = (label ?? '').toLowerCase();
    if (t.contains('air-gap') || t.contains('airgap')) {
      return Icons.qr_code_2_outlined;
    }
    if (t == 'watch-only' || t.contains('watch only')) {
      return Icons.visibility_outlined;
    }
    if (t.contains('multisig') || RegExp(r'\d+-of-\d+').hasMatch(t)) {
      return Icons.groups_outlined;
    }
    if (t.contains('hardware') ||
        t.contains('jade') ||
        t.contains('ledger') ||
        t.contains('usb')) {
      return Icons.usb_outlined;
    }
    return Icons.vpn_key_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final parts = partsOf(wallet, compact: compact);
    final fp = wallet.masterFingerprint;
    final ink = color ?? s.inkSecondary;
    final hasFp = fp != null && fp.isNotEmpty;

    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            parts.join('  ·  '),
            style: AppTypography.caption.copyWith(color: ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // The slot is reserved even when there is no fingerprint (a
          // coordinator-built multisig has none), so headlines and fact lines
          // stay on one baseline across a row of tiles.
          Text(
            hasFp ? fp : '',
            style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    return Text.rich(
      TextSpan(
        style: AppTypography.caption.copyWith(color: ink),
        children: [
          TextSpan(text: parts.join('  ·  ')),
          // The fingerprint stays monospaced: it is a value to compare
          // character by character, not prose.
          //
          // No fallback when it is missing. The obvious one — the threshold —
          // is ALREADY the key-origin label for a multisig, and appending it
          // here printed "2-of-3 · BTC only · 2-of-3".
          if (hasFp) ...[
            const TextSpan(text: '  ·  '),
            TextSpan(
              text: fp,
              style: AppTypography.monoSmall.copyWith(color: ink),
            ),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

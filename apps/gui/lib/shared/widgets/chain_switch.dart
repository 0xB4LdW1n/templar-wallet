import 'package:flutter/material.dart';

import 'asset_logo.dart';
import 'segmented_switch.dart';

/// The Bitcoin / Liquid switch that sits top-right on every screen whose
/// content is per chain (UTXOs, Activity, Receive) — the same control in the
/// same place.
///
/// It is the plain [SegmentedSwitch]: the chain is named by its label and
/// identified by its logo ([AssetLogo]), whether chosen or not. The hue never
/// fills, outlines or colours the label.
///
/// Always drawn, even for a wallet with one chain: the chain the wallet lacks
/// is shown dimmed with a tooltip instead of vanishing. A missing control
/// reads as a bug; a dimmed one as a fact about this wallet. On a phone the
/// reason surfaces as a snack bar when the dimmed segment is tapped.
///
/// Screens keep their own value vocabulary ('BTC' / 'Liquid', 'BTC' / 'LBTC',
/// 'bitcoin' / 'liquid'), so the values are passed in rather than fixed here.
class ChainSwitch<T> extends StatelessWidget {
  const ChainSwitch({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.bitcoin,
    required this.liquid,
    this.all,
    this.bitcoinEnabled = true,
    this.liquidEnabled = true,
    this.expand = false,
    this.iconOnly = false,
  });

  final T selected;
  final ValueChanged<T> onChanged;

  /// Value the caller uses for the Bitcoin chain.
  final T bitcoin;

  /// Value the caller uses for the Liquid chain.
  final T liquid;

  /// Optional leading "All" choice (the Activity filter).
  final T? all;

  final bool bitcoinEnabled;
  final bool liquidEnabled;

  /// Span the full width with equal segments — the phone layout when the
  /// switch gets its own row under the title. Needs a bounded width; see
  /// [SegmentedSwitch.expand].
  final bool expand;

  /// Logos only, names in the tooltip / semantics — for a phone row the
  /// switch has to share with other controls.
  final bool iconOnly;

  static const _bitcoinLogo = AssetLogo(
    ticker: 'BTC',
    size: SegmentedSwitch.logoSize,
  );
  static const _liquidLogo = AssetLogo(
    ticker: 'LIQUID',
    size: SegmentedSwitch.logoSize,
  );

  @override
  Widget build(BuildContext context) {
    return SegmentedSwitch<T>(
      selected: selected,
      onChanged: onChanged,
      expand: expand,
      iconOnly: iconOnly,
      options: [
        if (all != null)
          SegOption(
            value: all as T,
            label: 'All',
            icon: iconOnly ? Icons.all_inclusive : null,
          ),
        SegOption(
          value: bitcoin,
          label: 'Bitcoin',
          logo: _bitcoinLogo,
          enabled: bitcoinEnabled,
          tooltip: bitcoinEnabled ? null : 'This wallet has no Bitcoin side',
        ),
        SegOption(
          value: liquid,
          label: 'Liquid',
          logo: _liquidLogo,
          enabled: liquidEnabled,
          tooltip: liquidEnabled
              ? null
              : 'Liquid is not enabled for this wallet — turn it on from Wallet info',
        ),
      ],
    );
  }
}

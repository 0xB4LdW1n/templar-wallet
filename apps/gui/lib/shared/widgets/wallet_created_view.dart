import 'package:flutter/material.dart';

import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// One summary row on the wallet-created screen.
class WalletCreatedDetail {
  const WalletCreatedDetail(this.label, this.value, {this.mono = false});

  final String label;
  final String value;

  /// A value compared character by character (a key, a descriptor, a
  /// fingerprint): set in mono and selectable.
  final bool mono;
}

/// The last step of every setup flow: a calm statement of what now exists.
///
/// The flow's step header already says "Wallet created" in the display
/// size, so this view does not repeat it. It is one line of what the wallet
/// can do and the wallet's facts as key/value rows on one card — the name
/// first. No seal (creating a wallet is not a signature), no glowing check,
/// nothing that bounces.
class WalletCreatedView extends StatelessWidget {
  const WalletCreatedView({
    required this.walletName,
    this.subtitle,
    this.details = const [],
    super.key,
  });

  final String walletName;

  /// One line above the facts, e.g. "2-of-3 multisig — 2 keys required".
  final String? subtitle;

  /// The facts, in the order given, after the name.
  final List<WalletCreatedDetail> details;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final rows = [WalletCreatedDetail('Name', walletName), ...details];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          subtitle ?? 'Your wallet is ready',
          style: AppTypography.bodyOf(context).copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        Container(
          decoration: BoxDecoration(
            color: s.panel,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: s.edge),
            boxShadow: s.panelShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: s.edge),
                _FactRow(detail: rows[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A key in the secondary ink in a fixed column, the value in the primary
/// ink beside it. On a phone a long mono value (a key, a descriptor) goes
/// under its key so it gets the whole width.
class _FactRow extends StatelessWidget {
  const _FactRow({required this.detail});

  final WalletCreatedDetail detail;

  static const double _keyWidth = 112;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final key = Text(
      detail.label,
      style: AppTypography.label.copyWith(color: s.inkSecondary),
    );
    final value = detail.mono
        ? SelectableText(
            detail.value,
            style: AppTypography.mono.copyWith(color: s.ink),
          )
        : Text(detail.value, style: AppTypography.body.copyWith(color: s.ink));
    final stack = AppLayout.isPhone(context) && detail.mono;
    return Container(
      constraints: const BoxConstraints(minHeight: AppSpacing.xxxl),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: stack
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                key,
                const SizedBox(height: AppSpacing.xs),
                value,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: _keyWidth, child: key),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: value),
              ],
            ),
    );
  }
}

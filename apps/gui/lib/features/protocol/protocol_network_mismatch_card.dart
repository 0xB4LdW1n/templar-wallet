import 'package:flutter/material.dart';

import '../../bridge/wallet_bridge.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'models/protocol_link.dart';

/// What a site asks for and what the wallet is on, when they disagree.
///
/// This replaces the generic error card for [ProtocolNetworkMismatch] alone. The
/// old message ended the flow — "switch the Liquid network in Settings" meant
/// leaving the screen, finding the setting, guessing the regtest asset id and
/// pasting the link again. Here the switch is the primary action, on the
/// screen that found the problem, and the request is retried after it.
///
/// Three states, because only some mismatches have a way out:
///   * switchable — Templar runs the site's network (or its regtest chain);
///   * locked     — `TEMPLAR_LIQUID_NETWORK` fixes the network for this run;
///   * unsupported— Liquid mainnet, or a name this build does not know.
/// The last two offer only the way to Settings: no button that cannot work.
class ProtocolNetworkMismatchCard extends StatefulWidget {
  const ProtocolNetworkMismatchCard({
    super.key,
    required this.mismatch,
    required this.onSwitch,
    required this.onOpenSettings,
    this.info,
    this.busy = false,
  });

  final ProtocolNetworkMismatch mismatch;

  /// Runs the shared switch with the asset id shown in the field (null on
  /// testnet, where there is nothing to choose).
  final void Function(String? policyAsset) onSwitch;

  /// Deep link to Settings › Network.
  final VoidCallback onOpenSettings;

  /// The engine's current Liquid state: whether the network is locked by the
  /// environment, and the stock regtest asset id to prefill. Null while it is
  /// still being read — the card then behaves as if nothing were locked.
  final LiquidNetworkInfo? info;

  final bool busy;

  @override
  State<ProtocolNetworkMismatchCard> createState() =>
      _ProtocolNetworkMismatchCardState();
}

class _ProtocolNetworkMismatchCardState
    extends State<ProtocolNetworkMismatchCard> {
  late final TextEditingController _policyAsset = TextEditingController(
    text:
        widget.mismatch.policyAssetFor(
          widget.info?.regtestDefaultPolicyAsset ?? '',
        ) ??
        '',
  );

  @override
  void dispose() {
    _policyAsset.dispose();
    super.dispose();
  }

  bool get _locked => widget.info?.envLocked ?? false;

  /// The label of the one action that moves this forward.
  String get _switchLabel => switch (widget.mismatch.kind) {
    ProtocolMismatchKind.chain => "Switch this wallet to the site's chain",
    _ =>
      'Switch this wallet to '
          '${protocolNetworkLabel(widget.mismatch.siteNetwork)}',
  };

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final m = widget.mismatch;
    final phone = AppLayout.isPhone(context);
    final canSwitch = m.canSwitch && !_locked;
    final needsAsset = canSwitch && m.targetShortName == 'regtest';

    final switchButton = canSwitch
        ? PrimaryButton(
            key: const Key('protocol-mismatch-switch'),
            label: _switchLabel,
            isLoading: widget.busy,
            isFullWidth: phone,
            onPressed: widget.busy
                ? null
                : () => widget.onSwitch(
                    needsAsset ? _policyAsset.text.trim() : null,
                  ),
          )
        : null;
    final settingsButton = SecondaryButton(
      key: const Key('protocol-mismatch-settings'),
      label: 'Open Network settings',
      isFullWidth: phone,
      onPressed: widget.busy ? null : widget.onOpenSettings,
    );

    return FormCard(
      title: 'Wrong network',
      subtitle: m.kind == ProtocolMismatchKind.chain
          ? 'Same network name, different chain — the two nodes do not share '
                'an LBTC asset, so nothing signed on one is valid on the other'
          : 'A wallet only signs on the chain it is running',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The two names exactly as the site and the engine give them, in
          // mono: the difference may be one word.
          KvRow(label: 'The site', value: m.siteNetwork, labelWidth: 112),
          KvRow(label: 'This wallet', value: m.walletNetwork, labelWidth: 112),
          const SizedBox(height: AppSpacing.md),
          DangerBanner(message: m.message),
          const SizedBox(height: AppSpacing.lg),
          if (!m.canSwitch)
            Text(
              'This build runs Liquid testnet, a test server\'s Liquid regtest '
              'and a local Liquid regtest. Open the site for one of those, or '
              'join the test server it belongs to.',
              style: AppTypography.bodyOf(
                context,
              ).copyWith(color: s.inkSecondary),
            )
          else if (_locked)
            const InfoBanner(
              title: 'The network is fixed for this session',
              message:
                  'TEMPLAR_LIQUID_NETWORK sets it for this run of the app, '
                  'so it cannot be switched from here. Unset the variable and '
                  'start Templar again, then open the link once more.',
            )
          else ...[
            if (needsAsset) ...[
              Text(
                'Regtest LBTC asset id',
                style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('protocol-mismatch-policy'),
                controller: _policyAsset,
                enabled: !widget.busy,
                style: AppTypography.mono.copyWith(color: s.ink),
                decoration: InputDecoration(
                  hintText: widget.info?.regtestDefaultPolicyAsset,
                  helperText: m.sitePolicyAsset != null
                      ? 'Sent by the site with this request. Edit it only if '
                            'you know your node uses another one.'
                      : 'The site did not name one, so the stock '
                            'liquidregtest id is used. Your node reports its own '
                            'with elements-cli dumpassetlabels.',
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            const WarningBanner(
              message:
                  'Switching closes the open wallet. Templar reopens this '
                  'request straight after, and you pick the wallet again.',
            ),
          ],
          SizedBox(height: phone ? AppSpacing.lg : AppSpacing.xl),
          if (phone) ...[
            if (switchButton != null) ...[
              switchButton,
              const SizedBox(height: AppSpacing.sm),
            ],
            settingsButton,
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                settingsButton,
                if (switchButton != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(child: switchButton),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

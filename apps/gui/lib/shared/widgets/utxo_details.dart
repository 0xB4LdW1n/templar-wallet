// The coin details sheet — what the "i" on every UTXO opens.
//
// A dialog on desktop, a bottom sheet on a phone (showAppDialog), holding
// everything the row or note could not: the whole outpoint, the address it
// sits on, the asset id, the confirmation count and the rule that put it in
// its tier, as key/value rows — plus a copy of the outpoint, the one way out
// to a block explorer and, on the coin screen, Freeze / Unfreeze. Neutral
// throughout: the sheet informs, it has no primary action.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../features/utxos/models/utxo.dart';
import '../../services/address_label_store.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'buttons.dart';
import 'hybrid_kit.dart';
import 'app_dialog.dart';
import 'privacy.dart';
import 'utxo_views.dart';

/// Opens the details sheet for [utxo]. [share] is its slice of the asset's
/// holdings and [tier] the note size that follows from it — both are passed
/// in rather than recomputed so the sheet says exactly what the row said.
/// With [onToggleFrozen] the sheet offers Freeze / Unfreeze; it closes
/// itself before calling it.
Future<void> showUtxoDetails(
  BuildContext context, {
  required Utxo utxo,
  required double share,
  required BanknoteTier tier,
  VoidCallback? onToggleFrozen,
}) {
  // Read the explorer bases here, on the caller's tree: the dialog route
  // sits under the root navigator and may not see the same providers.
  String btcBase = 'https://mempool.space/testnet';
  String liquidBase = 'https://blockstream.info/liquidtestnet';
  try {
    final st = context.read<AppState>();
    btcBase = st.btcExplorerUrl;
    liquidBase = st.liquidExplorerUrl;
  } on ProviderNotFoundException {
    // A bare test host without AppState: the defaults above still make a
    // valid link.
  }
  return showAppDialog<void>(
    context,
    builder: (ctx) => UtxoDetailsDialog(
      utxo: utxo,
      share: share,
      tier: tier,
      explorerBase: utxo.assetId == null ? btcBase : liquidBase,
      // A coin still in the mempool cannot be picked, so it cannot be
      // frozen either.
      onToggleFrozen: utxo.isPending ? null : onToggleFrozen,
    ),
  );
}

class UtxoDetailsDialog extends StatelessWidget {
  const UtxoDetailsDialog({
    super.key,
    required this.utxo,
    required this.share,
    required this.tier,
    required this.explorerBase,
    this.onToggleFrozen,
  });

  final Utxo utxo;
  final double share;
  final BanknoteTier tier;

  /// Freezes or unfreezes the coin; null hides the button.
  final VoidCallback? onToggleFrozen;

  /// The block explorer for this coin's chain, without a trailing slash.
  final String explorerBase;

  String get _explorerUrl {
    final base = explorerBase.endsWith('/')
        ? explorerBase.substring(0, explorerBase.length - 1)
        : explorerBase;
    return '$base/tx/${utxo.txid}';
  }

  Future<void> _openExplorer(BuildContext context) async {
    final url = _explorerUrl;
    // launchUrl answers false (or throws on some OEM builds and restricted
    // work profiles) when nothing can take an https VIEW intent; a silent
    // no-op there reads as a dead button, so the link goes to the clipboard
    // with a word about it.
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text("Couldn't open a browser — explorer link copied"),
      ),
    );
  }

  String get _stateText => switch (utxo.state) {
    UtxoState.available => 'Available',
    UtxoState.frozen => 'Frozen',
    UtxoState.dusty => 'Dust',
    UtxoState.unconfirmed => 'Pending',
  };

  String get _confirmationsText {
    if (utxo.isPending || utxo.confirmations == 0) {
      return 'In the mempool, not in a block yet';
    }
    return utxo.confirmations == 1
        ? '1 confirmation'
        : '${utxo.confirmations} confirmations';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final pending = utxo.isPending;
    final assetName = utxo.ticker ?? 'BTC';
    final caption = AppTypography.caption.copyWith(color: s.inkSecondary);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The money first, then its tier and share and the bar that draws
        // the share.
        Amount(
          utxo.displayAmount,
          style: AppTypography.numericLargeOf(
            context,
          ).copyWith(color: pending ? s.inkSecondary : s.ink),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          pending
              ? 'Pending · ${utxoShareText(share)} of your $assetName once '
                    'it confirms'
              : '${tier.label} · ${utxoShareText(share)} of your $assetName',
          style: caption,
        ),
        const SizedBox(height: AppSpacing.sm),
        ShareMeter(share: share),
        if (!pending) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(tier.rule, style: caption),
        ],
        if (utxo.isFrozen) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Frozen: this wallet will not spend it — not in a payment, not '
            'in MAX, not in a consolidation — until you unfreeze it.',
            style: caption,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Divider(height: 1, thickness: 1, color: s.edge),
        KvRow(
          label: 'Outpoint',
          value: utxo.outpoint,
          labelWidth: 112,
          divider: true,
        ),
        if (utxo.address case final address?) ...[
          KvRow(
            label: 'Address',
            value: address,
            labelWidth: 112,
            divider: true,
          ),
          // What the user called the address, beside what they called the
          // coin further down: the two labels are different things.
          if (AddressLabelStore.instance.labelFor(address) case final name?)
            KvRow(
              label: 'Address label',
              value: name,
              labelWidth: 112,
              divider: true,
            ),
        ],
        KvRow(
          label: 'Amount',
          value: maskAmount(context, utxo.displayAmount),
          labelWidth: 112,
          divider: true,
        ),
        KvRow(
          label: 'Confirmations',
          value: _confirmationsText,
          labelWidth: 112,
          divider: true,
        ),
        KvRow(
          label: 'State',
          value: _stateText,
          labelWidth: 112,
          divider: true,
        ),
        if (utxo.label case final label?)
          KvRow(label: 'Label', value: label, labelWidth: 112, divider: true),
        if (utxo.assetId case final assetId?)
          KvRow(
            label: 'Asset ID',
            value: assetId,
            labelWidth: 112,
            divider: true,
          ),
      ],
    );

    final copy = _CopyOutpointButton(outpoint: utxo.outpoint);
    final explorer = GhostButton(
      label: 'Open in explorer',
      onPressed: () => _openExplorer(context),
    );
    final Widget? freeze = switch (onToggleFrozen) {
      final toggle? => SecondaryButton(
        label: utxo.isFrozen ? 'Unfreeze' : 'Freeze',
        onPressed: () {
          Navigator.of(context).pop();
          toggle();
        },
      ),
      null => null,
    };
    final close = SecondaryButton(
      label: 'Close',
      onPressed: () => Navigator.of(context).pop(),
    );

    // A row on desktop, read left to right with Close last. A phone's sheet
    // stacks its actions from the bottom up, so the list is turned round to
    // put the coin's own action on top, under the thumb, and Close at the
    // foot.
    return AppDialog(
      title: const Text('Coin details'),
      scrollable: true,
      content: SizedBox(width: phone ? double.infinity : 480, child: content),
      actions: phone
          ? [close, explorer, copy, ?freeze]
          : [copy, explorer, ?freeze, close],
    );
  }
}

// ── Label prompt ──────────────────────────────────────────────────────────────

/// The longest label the prompt takes: a name for a coin, not a note.
const int kUtxoLabelMaxLength = 64;

/// Asks for a coin's label. A dialog on desktop, a sheet on a phone
/// ([showAppDialog]).
///
/// Answers the trimmed label to save, an empty string to clear the one the
/// coin has, or null when the user cancelled. [current] fills the field and
/// offers "Clear label"; [count] above one titles it for a selection;
/// [outpoint] names the one coin being labelled.
///
/// A label is display metadata kept on this device: the prompt only says
/// what to show, the caller stores it.
Future<String?> showUtxoLabelPrompt(
  BuildContext context, {
  String? current,
  int count = 1,
  String? outpoint,
}) => showAppDialog<String>(
  context,
  builder: (_) =>
      UtxoLabelPrompt(current: current, count: count, outpoint: outpoint),
);

class UtxoLabelPrompt extends StatefulWidget {
  const UtxoLabelPrompt({
    super.key,
    this.current,
    this.count = 1,
    this.outpoint,
  });

  final String? current;
  final int count;
  final String? outpoint;

  @override
  State<UtxoLabelPrompt> createState() => _UtxoLabelPromptState();
}

class _UtxoLabelPromptState extends State<UtxoLabelPrompt> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.current ?? '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_ctrl.text.trim());

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final current = widget.current;
    final many = widget.count > 1;
    final title = many
        ? 'Label ${widget.count} coins'
        : (current == null ? 'Add label' : 'Edit label');
    return PromptDialog(
      title: title,
      icon: Icons.sell_outlined,
      width: 420,
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (current != null || many)
          GhostButton(
            label: 'Clear label',
            onPressed: () => Navigator.of(context).pop(''),
          ),
        PrimaryButton(label: 'Save', onPressed: _save),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.outpoint case final outpoint? when !many) ...[
            Text(
              outpoint,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Text(
            'Label',
            style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: kUtxoLabelMaxLength,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Savings, exchange withdrawal',
              counterText: '',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Kept on this device only',
            style: AppTypography.caption.copyWith(color: s.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// "Copy outpoint" that turns into "Copied" for a moment — the same small
/// reward a code box's copy button gives.
class _CopyOutpointButton extends StatefulWidget {
  const _CopyOutpointButton({required this.outpoint});
  final String outpoint;

  @override
  State<_CopyOutpointButton> createState() => _CopyOutpointButtonState();
}

class _CopyOutpointButtonState extends State<_CopyOutpointButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.outpoint));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) => GhostButton(
    label: _copied ? 'Copied' : 'Copy outpoint',
    icon: _copied ? Icons.check : null,
    onPressed: _copy,
  );
}

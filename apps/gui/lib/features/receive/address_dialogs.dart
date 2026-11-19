// What can be done with one address from a list: give it a label, and open
// it — its QR, the address in full, its facts — in the app's dialog (a sheet
// on a phone). Receive and All addresses both open these.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/address_label_store.dart';
import '../../shared/widgets/address_tag.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'address_rows.dart';
import 'models/address_info.dart';

/// The label shown for [info]: the one the user wrote, else the engine's.
String? addressLabelOf(AddressInfo info) =>
    AddressLabelStore.instance.labelFor(info.address) ?? info.label;

/// Asks for the mark of [address] — its label and the colour of its tag —
/// and saves it. Clearing the field removes the user's label (an engine
/// label, if there is one, shows again). [index] is the address's
/// derivation index, printed beside it when the caller knows it (a coin's
/// address comes without one).
Future<void> showAddressLabelPrompt(
  BuildContext context, {
  required String address,
  int? index,
}) {
  return showAppDialog<void>(
    context,
    builder: (_) => _AddressLabelDialog(address: address, index: index),
  );
}

class _AddressLabelDialog extends StatefulWidget {
  const _AddressLabelDialog({required this.address, this.index});
  final String address;
  final int? index;

  @override
  State<_AddressLabelDialog> createState() => _AddressLabelDialogState();
}

class _AddressLabelDialogState extends State<_AddressLabelDialog> {
  static final AddressLabelStore _store = AddressLabelStore.instance;

  late final TextEditingController _ctrl = TextEditingController(
    text: _store.labelFor(widget.address) ?? '',
  );

  /// The colour on show: the user's pick, else grey, so the dialog opens
  /// on the tag as it is drawn. Grey is stored as no pick at all.
  late int _hue = _store.hueFor(widget.address);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _ctrl.text.trim();
    await _store.setMark(widget.address, label: label, hue: _hue);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    await _store.setMark(widget.address, label: '', hue: null);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final had =
        _store.labelFor(widget.address) != null ||
        _store.pickedHueFor(widget.address) != null;
    final index = widget.index;
    final text = _ctrl.text.trim();
    Widget eyebrow(String t) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        t,
        style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
      ),
    );
    return PromptDialog(
      title: had ? 'Edit label' : 'Label address',
      icon: Icons.label_outlined,
      actions: [
        if (had)
          GhostButton(
            label: 'Remove label',
            isFullWidth: phone,
            onPressed: _remove,
          )
        else
          GhostButton(
            label: 'Cancel',
            isFullWidth: phone,
            onPressed: () => Navigator.of(context).pop(),
          ),
        PrimaryButton(label: 'Save', isFullWidth: phone, onPressed: _save),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The tag as it will be drawn, beside the address it names.
          Row(
            children: [
              AddressTag(
                label: text.isEmpty ? 'Label' : text,
                hue: tagHue(s, _hue),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  index == null
                      ? shortAddress(widget.address)
                      : '#$index · ${shortAddress(widget.address)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.monoSmall.copyWith(
                    color: s.inkSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          eyebrow('Label'),
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLength: AddressLabelStore.maxLength,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Rent, exchange, a name',
              counterText: '',
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.lg),
          eyebrow('Colour'),
          TagHuePicker(
            selected: _hue,
            onChanged: (i) => setState(() => _hue = i),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Shown wherever this address is listed. Kept on this device only',
            style: AppTypography.caption.copyWith(color: s.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// Opens [info]: its QR, the address in full, what it received, its label.
/// [coin] is the chain's whole-coin unit (`BTC` or `LBTC`).
Future<void> showAddressDetail(
  BuildContext context, {
  required AddressInfo info,
  required String coin,
  required bool useSats,
  String? status,
}) {
  return showAppDialog<void>(
    context,
    builder: (_) => _AddressDetail(
      info: info,
      coin: coin,
      useSats: useSats,
      status: status,
    ),
  );
}

class _AddressDetail extends StatefulWidget {
  const _AddressDetail({
    required this.info,
    required this.coin,
    required this.useSats,
    this.status,
  });

  final AddressInfo info;
  final String coin;
  final bool useSats;
  final String? status;

  @override
  State<_AddressDetail> createState() => _AddressDetailState();
}

class _AddressDetailState extends State<_AddressDetail> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.info.address));
    if (!mounted) return;
    confirmCopyOnPhone(context);
    setState(() => _copied = true);
    await Future.delayed(kCopiedFor);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final a = widget.info;
    final figure = receivedFigure(
      a.receivedSats,
      useSats: widget.useSats,
      coin: widget.coin,
    );
    final side = phone ? AppLayout.qrSide(context) : 216.0;
    return ListenableBuilder(
      listenable: AddressLabelStore.instance,
      builder: (context, _) {
        final label = addressLabelOf(a);
        void editLabel() =>
            showAddressLabelPrompt(context, address: a.address, index: a.index);
        return AppDialog(
          title: Text(label ?? 'Address #${a.index}'),
          scrollable: true,
          content: SizedBox(
            width: phone ? null : 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  // White in both themes: a code needs its quiet zone, and
                  // a camera reads dark modules on white.
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: SizedBox.square(
                      dimension: side,
                      child: QrImageView(
                        data: a.address,
                        version: QrVersions.auto,
                        size: side,
                        padding: EdgeInsets.zero,
                        semanticsLabel: 'Address QR code',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                DataWell(
                  child: SelectableText(
                    a.address,
                    style: AppTypography.mono.copyWith(color: s.ink),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                KvRow(label: 'Index', value: '#${a.index}', divider: true),
                if (widget.status != null)
                  KvRow(label: 'Status', value: widget.status!, divider: true),
                KvRow(
                  label: 'Received',
                  value: a.receivedSats > 0
                      ? '${figure.value} ${figure.unit}'
                      : 'Nothing yet',
                  divider: true,
                ),
                if (a.derivationPath != null)
                  KvRow(label: 'Path', value: a.derivationPath!, divider: true),
                // The form an explorer shows: the blinding key in the
                // address above never goes on chain.
                if (a.unconfidentialAddress case final plain?)
                  KvRow(label: 'On explorers', value: plain, divider: true),
                _LabelRow(
                  tag: label == null
                      ? AddAddressTag(onTap: editLabel)
                      : AddressTag(
                          label: label,
                          hue: addressHueOf(s, a.address),
                          onTap: editLabel,
                          tooltip: 'Edit label',
                        ),
                ),
              ],
            ),
          ),
          actions: [
            GhostButton(
              label: label == null ? 'Add label' : 'Edit label',
              icon: Icons.label_outlined,
              onPressed: editLabel,
            ),
            SecondaryButton(
              label: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
            PrimaryButton(
              label: _copied ? 'Copied' : 'Copy address',
              icon: _copied ? Icons.check_outlined : Icons.copy_outlined,
              onPressed: _copy,
            ),
          ],
        );
      },
    );
  }
}

/// The label fact of an address's detail: the key in its column, the tag —
/// which is its own editor — where a value would be.
class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.tag});
  final Widget tag;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              'Label',
              style: AppTypography.label.copyWith(color: s.inkSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(child: tag),
        ],
      ),
    );
  }
}

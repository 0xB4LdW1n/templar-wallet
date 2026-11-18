// Naming one co-signer: a name, a glyph and a colour.
//
// One editor, two callers — the creation wizard, where the wallet does not
// exist yet and the label is held in memory, and Appearance, where it is
// written straight to the store. Neither knows about the other, so the widget
// takes a label in and hands one back.

import 'package:flutter/material.dart';

import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../models/cosigner_label.dart';
import 'buttons.dart';
import 'app_dialog.dart';
import 'list_rows.dart';

/// Opens the editor for [label]. Returns the edited label, or null if
/// dismissed.
///
/// [subtitle] says which key is being named — a fingerprint and path, or the
/// source it came from — because "Key 2" alone is not enough to know which
/// device is being described.
Future<CosignerLabel?> showCosignerLabelEditor(
  BuildContext context, {
  required CosignerLabel label,
  required int index,
  String? subtitle,
}) {
  return showAppDialog<CosignerLabel>(
    context,
    builder: (_) =>
        _CosignerLabelDialog(label: label, index: index, subtitle: subtitle),
  );
}

class _CosignerLabelDialog extends StatefulWidget {
  const _CosignerLabelDialog({
    required this.label,
    required this.index,
    this.subtitle,
  });

  final CosignerLabel label;
  final int index;
  final String? subtitle;

  @override
  State<_CosignerLabelDialog> createState() => _CosignerLabelDialogState();
}

class _CosignerLabelDialogState extends State<_CosignerLabelDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.label.name ?? '',
  );
  late String? _iconId = widget.label.iconId;
  late int? _color = widget.label.colorValue;

  /// Starts at what the label already implies, so an old label whose USB
  /// icon has been standing in for the flag shows the switch on.
  late bool _hardware = widget.label.isHardware;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return AppDialog(
      title: Text('Name key ${widget.index + 1}'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.subtitle case final sub?) ...[
              Text(
                sub,
                style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            const ListSectionLabel(label: 'Name'),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 40,
              style: AppTypography.bodyOf(context).copyWith(color: s.ink),
              decoration: const InputDecoration(
                hintText: 'Jade in the safe',
                counterText: '',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.xl),
            const ListSectionLabel(label: 'Icon'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final entry in cosignerIcons.entries)
                  _IconSwatch(
                    selected: _iconId == entry.key,
                    icon: entry.value,
                    onTap: () => setState(
                      () => _iconId = _iconId == entry.key ? null : entry.key,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const ListSectionLabel(label: 'Colour'),
            Wrap(
              spacing: phone ? 0 : AppSpacing.xs,
              runSpacing: phone ? 0 : AppSpacing.xs,
              children: [
                for (final value in cosignerColors)
                  _ColorSwatch(
                    selected: _color == value,
                    color: Color(value),
                    onTap: () =>
                        setState(() => _color = _color == value ? null : value),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const ListSectionLabel(label: 'Signs on'),
            // Where the key lives, for whoever reads a signer list: a
            // flagged key wears the USB glyph. Presentation like the rest of
            // the label — the co-signing sheet offers USB either way.
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: s.panelInset,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.usb_outlined,
                    size: AppSpacing.icon,
                    color: s.inkSecondary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'USB hardware wallet',
                          style: AppTypography.body.copyWith(
                            color: s.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'A Ledger or Jade connected over USB. Signer '
                          'lists mark this key with the USB glyph.',
                          style: AppTypography.caption.copyWith(
                            color: s.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ListSwitch(
                    value: _hardware,
                    onChanged: (v) => setState(() => _hardware = v),
                    semanticLabel: 'Signs on a USB hardware wallet',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PrimaryButton(label: 'Save', onPressed: _submit),
      ],
    );
  }

  void _submit() {
    // The flag is only written down once somebody has actually said: a label
    // that was merely inferring from its icon keeps inferring, so changing
    // the icon later still changes the answer.
    final explicit =
        widget.label.hardware != null || _hardware != widget.label.isHardware;
    Navigator.of(context).pop(
      CosignerLabel(
        id: widget.label.id,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        iconId: _iconId,
        colorValue: _color,
        hardware: explicit ? _hardware : null,
      ),
    );
  }
}

/// One glyph to choose. Selection is a surface step and a firmer edge, as
/// everywhere else — the glyph never takes a colour.
class _IconSwatch extends StatelessWidget {
  const _IconSwatch({
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final side = AppLayout.isPhone(context) ? AppLayout.minTouchTarget : 40.0;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        hoverColor: s.hover,
        splashFactory: NoSplash.splashFactory,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          width: side,
          height: side,
          decoration: BoxDecoration(
            color: selected ? s.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: selected ? s.edgeStrong : s.edge),
          ),
          child: Icon(
            icon,
            size: AppSpacing.icon,
            color: selected ? s.ink : s.inkSecondary,
          ),
        ),
      ),
    );
  }
}

/// One colour to choose: a 24 px disc. Chosen, it gets a 2 px ring in the
/// primary ink, 2 px out from the disc.
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    // 24 disc + 2 gap + 2 ring on each side = 32; a phone pads the target
    // out to 48 around it.
    final target = AppLayout.isPhone(context) ? AppLayout.minTouchTarget : 32.0;
    return Semantics(
      button: true,
      selected: selected,
      child: InkResponse(
        onTap: onTap,
        radius: target / 2,
        splashFactory: NoSplash.splashFactory,
        child: SizedBox(
          width: target,
          height: target,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? s.ink : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// The pieces every Settings page is built from (design.md, "Rows, not a card
// each").
//
// A page is a run of groups. A group is a quiet label, ONE card of rows, and —
// when the subject needs more than a one-line subtitle — a paragraph under the
// card. A setting is a row: its glyph on a neutral tile, its name, one line
// saying what it does, and the control that operates it on the right.
//
// [SettingsRow] exists beside the kit's `ListRow` because a setting sometimes
// shows a value that has to be read character by character (an endpoint, a
// directory) or a status that is a fact (a 6 px dot); it keeps ListRow's
// geometry to the pixel so the two can share a card.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/widgets/list_rows.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The space between two groups: a label sits 8 above its card (the label
/// owns that) and 24 below the block before it.
class SettingsGap extends StatelessWidget {
  const SettingsGap({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(height: AppSpacing.xl);
}

/// The paragraph under a card: the explanation a one-line subtitle cannot
/// hold. Security guidance lives here, so it is set in the secondary ink —
/// readable, not the faint meta grey — and capped at a readable measure.
class SettingsNote extends StatelessWidget {
  const SettingsNote({super.key, required this.text, this.color});

  final String text;

  /// Overrides the ink where the note states a failure (the danger ink).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      // Aligned, so a stretching parent cannot widen the measure past 640.
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.formMaxWidth),
          child: Text(
            text,
            style: AppTypography.caption.copyWith(
              color: color ?? s.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// One group: label, card, optional paragraph, optional control under it.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({
    super.key,
    this.label,
    required this.children,
    this.note,
    this.noteColor,
    this.footer,
    this.blocks = false,
  });

  final String? label;
  final List<Widget> children;
  final String? note;
  final Color? noteColor;

  /// A control that belongs to the whole group (a full-width phone button),
  /// placed 16 under the paragraph.
  final Widget? footer;

  /// The card holds blocks (fields, a grid) rather than rows with a glyph
  /// column, so its hairlines run from the card's own inset.
  final bool blocks;

  @override
  Widget build(BuildContext context) {
    final l = label;
    final n = note;
    final f = footer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (l != null) ListSectionLabel(label: l),
        if (blocks)
          SettingsCard(indent: kListPad, children: children)
        else
          ListCard(children: children),
        if (n != null) SettingsNote(text: n, color: noteColor),
        if (f != null) ...[const SizedBox(height: AppSpacing.lg), f],
      ],
    );
  }
}

/// [ListCard]'s material with a chosen divider inset — for a card whose
/// children are blocks rather than rows with a glyph column.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.children,
    this.indent = kListTextInset,
  });

  final List<Widget> children;
  final double indent;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: s.edge, indent: indent),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A block inside a card: a field, a grid, a banner — padded like a row.
class SettingsBlock extends StatelessWidget {
  const SettingsBlock({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.all(kListPad), child: child);
}

/// The 6 px status dot — a fact (encrypted, verified, failed), never
/// decoration.
class SettingsDot extends StatelessWidget {
  const SettingsDot(this.color, {super.key});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A setting: glyph tile (or a [leading] of the same width), title, one line
/// of description, and the control on the right.
class SettingsRow extends StatefulWidget {
  const SettingsRow({
    super.key,
    this.icon,
    this.tint,
    this.leading,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.mono = false,
    this.dot,
    this.wrap = false,
    this.trailing,
    this.onTap,
    this.chevron = false,
  }) : assert(icon != null || leading != null);

  final IconData? icon;

  /// The glyph's colour when it is a fact (a status, a chain); see
  /// [ListIconTile.tint].
  final Color? tint;

  /// Replaces the glyph tile (a radio, an avatar); drawn in the tile's
  /// column so titles still start on one line.
  final Widget? leading;

  final String title;
  final String? subtitle;

  /// Overrides the subtitle ink — for a failure stated in the danger ink.
  final Color? subtitleColor;

  /// Sets the subtitle in `mono`: a value read character by character.
  final bool mono;

  /// A 6 px status dot before the subtitle.
  final Color? dot;

  /// Lets the title and subtitle wrap instead of ellipsising — for a value
  /// that must be read to its end (a path, an endpoint).
  final bool wrap;

  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final sub = widget.subtitle;
    final onTap = widget.onTap;
    final enabled = onTap != null;
    final dot = widget.dot;
    final maxLines = widget.wrap ? null : 1;
    final overflow = widget.wrap ? null : TextOverflow.ellipsis;

    final subStyle = (widget.mono ? AppTypography.mono : AppTypography.caption)
        .copyWith(color: widget.subtitleColor ?? s.inkSecondary);

    final content = Row(
      children: [
        SizedBox(
          width: kListTile,
          child: Center(
            child:
                widget.leading ??
                ListIconTile(icon: widget.icon!, tint: widget.tint),
          ),
        ),
        const SizedBox(width: kListGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                style: AppTypography.bodyOf(context).copyWith(color: s.ink),
                maxLines: maxLines,
                overflow: overflow,
              ),
              if (sub != null)
                Row(
                  children: [
                    if (dot != null) ...[
                      SettingsDot(dot),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Flexible(
                      // Selectable only when the row itself is not a tap
                      // target: selection would swallow the row's tap.
                      child: widget.mono && !enabled
                          ? SelectableText(
                              sub,
                              style: subStyle,
                              maxLines: maxLines,
                            )
                          : Text(
                              sub,
                              style: subStyle,
                              maxLines: maxLines,
                              overflow: overflow,
                            ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          widget.trailing!,
        ],
        if (widget.chevron) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.chevron_right_outlined,
            size: AppSpacing.icon,
            color: s.inkFaint,
          ),
        ],
      ],
    );

    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      color: !enabled
          ? Colors.transparent
          : _down
          ? s.pressed
          : _hover
          ? s.hover
          : Colors.transparent,
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      constraints: BoxConstraints(
        minHeight: phone && sub != null
            ? AppSpacing.rowHeight + AppSpacing.sm
            : AppSpacing.rowHeight,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.sm,
      ),
      child: content,
    );

    if (!enabled) return body;
    return Semantics(
      button: true,
      child: MergeSemantics(
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (v) => setState(() {
            _hover = v;
            if (!v) _down = false;
          }),
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// A row's current value on the right, quiet: what the chevron next to it
/// would change.
class SettingsValue extends StatelessWidget {
  const SettingsValue(this.text, {super.key, this.mono = false});
  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Text(
      text,
      style: (mono ? AppTypography.mono : AppTypography.body).copyWith(
        color: s.inkFaint,
      ),
    );
  }
}

/// Copy for a public value (an endpoint, a directory). Turns into a check for
/// a moment. Never used for a secret: those go through `SecretClipboard`.
class SettingsCopyButton extends StatefulWidget {
  const SettingsCopyButton({
    super.key,
    required this.value,
    this.tooltip = 'Copy',
  });

  final String value;
  final String tooltip;

  @override
  State<SettingsCopyButton> createState() => _SettingsCopyButtonState();
}

class _SettingsCopyButtonState extends State<SettingsCopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return IconButton(
      tooltip: _copied ? 'Copied' : widget.tooltip,
      onPressed: widget.value.isEmpty ? null : _copy,
      icon: Icon(
        _copied ? Icons.check_outlined : Icons.copy_outlined,
        size: AppLayout.isPhone(context) ? 20 : AppSpacing.icon,
        // Copied is a fact, so its check is the success green; at rest the
        // glyph takes the themed ink (the accent's under the pointer).
        color: _copied ? s.success : null,
      ),
    );
  }
}

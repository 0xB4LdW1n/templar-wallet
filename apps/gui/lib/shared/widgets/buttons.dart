import 'package:flutter/material.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

// The buttons (design.md, "Controls").
//
// One body, four voices. A screen has exactly one [PrimaryButton] — the thing
// the screen exists for, filled with the accent. Everything beside it is a
// neutral surface: [SecondaryButton] is the raised surface with a hairline,
// [GhostButton] is bare text until the pointer finds it, and [DangerButton]
// is the secondary surface with its label in the danger ink — destructive by
// its words and its icon, never by being a second red slab next to the first.
// The icon of a secondary or ghost button is drawn in the accent
// (`AppScheme.accentGlyph`): a small mark of the wallet's colour beside an
// ink label, never a second filled control.
//
// Nothing glows. Hover is a surface step, press is a 2% squeeze, keyboard
// focus is a ring.

enum _Voice { primary, secondary, ghost, danger }

class _Button extends StatefulWidget {
  const _Button({
    required this.voice,
    required this.label,
    required this.onPressed,
    this.icon,
    this.leading,
    this.isFullWidth = false,
    this.dense = false,
    this.isLoading = false,
    this.large = false,
  });

  final _Voice voice;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Drawn in the icon's slot in place of [icon]: a glyph the icon font
  /// does not carry, in a colour of its own (the double bolt of "Speed up").
  final Widget? leading;
  final bool isFullWidth;

  /// Phone only: a 44 dp slab for a run of inline actions that must share a
  /// row. Desktop buttons are already that compact and ignore it.
  final bool dense;

  /// Work is running: the icon slot becomes a spinner and the button goes
  /// inert. The caller keeps owning the label ("Reading…"), because only it
  /// knows what the wait is for.
  final bool isLoading;

  /// Desktop only: the screen's lead pair (Send and Receive, Restore and New
  /// wallet) — 48 tall, radius 12, a 16 px label. A phone button is already
  /// that size and ignores it.
  final bool large;

  @override
  State<_Button> createState() => _ButtonState();
}

class _ButtonState extends State<_Button> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _activate() {
    if (_enabled) widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final dense = phone && widget.dense;
    final large = !phone && widget.large;
    final enabled = _enabled;
    final lit = enabled && (_hover || _down);

    // A state layer of the button's own ink: lifts a dark fill, deepens a
    // light one, and steps a neutral surface the same way a hovered row does.
    Color layered(Color base, Color over) => Color.alphaBlend(
      over.withValues(alpha: _down ? 0.14 : (_hover ? 0.08 : 0)),
      base,
    );

    final Color fill;
    final Color edge;
    final Color ink;
    // The glyph's ink. A neutral button's icon is the one place it wears
    // the accent (design.md, "The accent"): the label stays ink, the mark
    // beside it is the wallet's colour.
    final Color glyphInk;
    switch (widget.voice) {
      case _Voice.primary:
        fill = enabled ? layered(s.accent, s.onAccent) : s.panelInset;
        edge = Colors.transparent;
        ink = enabled ? s.onAccent : s.inkFaint;
        glyphInk = ink;
      case _Voice.secondary:
        fill = enabled ? layered(s.panelInset, s.ink) : Colors.transparent;
        // Under the pointer the outline takes the accent too.
        edge = lit ? s.accentGlyph.withValues(alpha: 0.6) : s.edge;
        ink = enabled ? s.ink : s.inkFaint;
        glyphInk = enabled ? s.accentGlyph : ink;
      case _Voice.danger:
        fill = enabled ? layered(s.panelInset, s.danger) : Colors.transparent;
        edge = enabled ? s.danger.withValues(alpha: lit ? 0.6 : 0.32) : s.edge;
        ink = enabled ? s.danger : s.inkFaint;
        glyphInk = ink;
      case _Voice.ghost:
        fill = lit ? (_down ? s.pressed : s.hover) : Colors.transparent;
        edge = Colors.transparent;
        ink = !enabled ? s.inkFaint : (lit ? s.ink : s.inkSecondary);
        glyphInk = enabled ? s.accentGlyph : ink;
    }

    final height = phone
        ? (dense ? AppLayout.minTouchTarget - 4 : AppSpacing.phoneControlHeight)
        : (large ? AppSpacing.controlHeightLarge : AppSpacing.controlHeight);
    final radius = phone || large
        ? AppSpacing.radiusPhoneControl
        : AppSpacing.radiusMd;
    final iconSize = phone && !dense
        ? 20.0
        : (large ? AppSpacing.icon : AppSpacing.iconSmall);
    final ghost = widget.voice == _Voice.ghost;

    final content = Row(
      mainAxisSize: widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading) ...[
          SizedBox(
            width: iconSize - 2,
            height: iconSize - 2,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(ink),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ] else if (widget.leading != null) ...[
          widget.leading!,
          const SizedBox(width: AppSpacing.sm),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: iconSize, color: glyphInk),
          const SizedBox(width: AppSpacing.sm),
        ],
        // Flexible + ellipsis: a narrow host shortens the label rather than
        // striping the button. Costs nothing while the label fits.
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                (phone && !dense
                        ? AppTypography.buttonOf(context)
                        : (large
                              ? AppTypography.buttonLarge
                              : AppTypography.button))
                    .copyWith(color: ink),
          ),
        ),
      ],
    );

    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      width: widget.isFullWidth ? double.infinity : null,
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: phone
            ? (dense ? AppSpacing.md : AppSpacing.lg)
            : (large ? AppSpacing.xl : (ghost ? AppSpacing.md : AppSpacing.lg)),
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: edge),
      ),
      // The ring sits outside the fill, so it reads on any voice.
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: content,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() {
          _hover = v;
          if (!v) _down = false;
        }),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? _activate : null,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          child: AnimatedScale(
            scale: AppMotion.reduced(context) || !_down ? 1.0 : 0.98,
            duration: AppMotion.of(context, AppMotion.instant),
            curve: AppMotion.settle,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// The screen's one action: filled with the accent. One per screen.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isLoading = false,
    this.isFullWidth = false,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool isFullWidth;

  /// Desktop only — the screen's lead pair: 48 tall, a 16 px label.
  final bool large;

  @override
  Widget build(BuildContext context) => _Button(
    voice: _Voice.primary,
    label: label,
    onPressed: onPressed,
    icon: icon,
    isLoading: isLoading,
    isFullWidth: isFullWidth,
    large: large,
  );
}

/// Every other action: the raised surface and a hairline.
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.leading,
    this.isFullWidth = false,
    this.dense = false,
    this.isLoading = false,
    this.large = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// A glyph of its own in the icon's slot; see [_Button.leading].
  final Widget? leading;
  final bool isFullWidth;

  /// Phone only — a 44 dp slab for a row of inline actions.
  final bool dense;

  /// Spinner in the icon slot, button inert.
  final bool isLoading;

  /// Desktop only — the screen's lead pair: 48 tall, a 16 px label.
  final bool large;

  @override
  Widget build(BuildContext context) => _Button(
    voice: _Voice.secondary,
    label: label,
    onPressed: onPressed,
    icon: icon,
    leading: leading,
    isFullWidth: isFullWidth,
    dense: dense,
    isLoading: isLoading,
    large: large,
  );
}

/// A destructive action: delete, burn, forget. Its label is a verb and it
/// carries an icon wherever there is room — the colour is the third signal,
/// not the only one.
class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isFullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isFullWidth;

  @override
  Widget build(BuildContext context) => _Button(
    voice: _Voice.danger,
    label: label,
    onPressed: onPressed,
    icon: icon,
    isFullWidth: isFullWidth,
  );
}

/// A tertiary action: bare text until the pointer lands on it.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isFullWidth = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isFullWidth;

  @override
  Widget build(BuildContext context) => _Button(
    voice: _Voice.ghost,
    label: label,
    onPressed: onPressed,
    icon: icon,
    isFullWidth: isFullWidth,
  );
}

/// One option in a row of choices — the app's chip, and a segmented control
/// that ran out of room.
///
/// Unselected it is an outline; selected it is the raised surface with a
/// firmer edge, the primary ink and — the user's mark on what they chose —
/// the accent dot of a chosen radio. Never an accent fill or ring.
class ChoiceTile extends StatefulWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    this.icon,
    this.onSelected,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final bool selected;

  /// null = an option the user can see but not take. Keeping it in place
  /// rather than dropping it leaves the control the same shape on every
  /// screen; put the reason in [tooltip].
  final VoidCallback? onSelected;

  final String? tooltip;

  @override
  State<ChoiceTile> createState() => _ChoiceTileState();
}

class _ChoiceTileState extends State<ChoiceTile> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  /// Phone stand-in for the hover tooltip on a dimmed chip.
  void _explainDisabled() {
    final tip = widget.tooltip;
    if (tip == null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tip)));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final enabled = widget.onSelected != null;
    final selected = widget.selected;
    final lit = enabled && _hover;

    final fill = selected
        ? s.selected
        : lit
        ? s.hover
        : Colors.transparent;
    final edge = selected || lit ? s.edgeStrong : s.edge;
    final ink = !enabled
        ? s.inkFaint.withValues(alpha: 0.6)
        : selected || lit
        ? s.ink
        : s.inkSecondary;
    final radius = phone ? AppSpacing.radiusPhoneControl : AppSpacing.radiusMd;

    final chip = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      constraints: BoxConstraints(
        minHeight: phone ? AppLayout.minTouchTarget : 32,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: phone ? AppSpacing.lg : AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: edge),
      ),
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Chosen, the chip carries the dot of a chosen radio, in the
          // accent: the user's own mark. The fill, the edge and the ink
          // still say it without the colour. (A ring in the accent would
          // read as an error while the accent is red.)
          if (selected) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: s.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: phone ? AppSpacing.icon : AppSpacing.iconSmall,
              color: ink,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (selected ? AppTypography.label : AppTypography.caption)
                  .copyWith(color: ink),
            ),
          ),
        ],
      ),
    );

    final tappable = Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() {
          _hover = v;
          if (!v) _down = false;
        }),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onSelected?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled
              ? widget.onSelected
              : (phone ? _explainDisabled : null),
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          child: AnimatedScale(
            scale: AppMotion.reduced(context) || !_down ? 1.0 : 0.98,
            duration: AppMotion.of(context, AppMotion.instant),
            curve: AppMotion.settle,
            child: chip,
          ),
        ),
      ),
    );

    final tip = widget.tooltip;
    if (tip == null) return tappable;
    // A phone tap on a dimmed chip already explains it; a long-press tooltip
    // would only add a second, undiscoverable path.
    if (phone) return tappable;
    return Tooltip(message: tip, child: tappable);
  }
}

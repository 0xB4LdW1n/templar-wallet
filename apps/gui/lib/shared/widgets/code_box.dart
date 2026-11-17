import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'buttons.dart';
import 'app_dialog.dart';
import 'hex_text.dart';

// The code box (design.md, "Code box"): a value a user compares character by
// character, printed in mono on a recess cut into the card, with the ways to
// hand it over — copy, QR — as icon buttons at its edge. Copy turns into a
// check for a moment: the one small reward for a true thing having happened.

/// Longest value a single QR holds: byte mode at version 40, low error
/// correction. A descriptor, an xpub or a fingerprint is nowhere near it; a
/// signed PSBT is, and gets the animated UR codes instead.
const int kQrMaxChars = 2900;

/// How long a copy control shows its check.
const Duration _copiedFor = Duration(milliseconds: 1500);

/// Opens [value] as a QR — a dialog on desktop, a sheet on a phone — with the
/// value printed under the code so what is scanned can be read too.
Future<void> showValueQr(
  BuildContext context, {
  required String title,
  required String value,
  String? caption,
}) {
  return showAppDialog<void>(
    context,
    builder: (ctx) =>
        ValueQrDialog(title: title, value: value, caption: caption),
  );
}

/// The body [showValueQr] opens. Keyed by its payload so a test can read
/// back what a camera would (the package keeps `data` private).
///
/// The code sits on white whatever the theme: a scanner needs the contrast.
class ValueQrDialog extends StatelessWidget {
  const ValueQrDialog({
    super.key,
    required this.title,
    required this.value,
    this.caption,
  });

  final String title;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final tooLong = value.length > kQrMaxChars;
    final side = phone ? AppLayout.qrSide(context, max: 300) : 300.0;
    return AppDialog(
      title: Text(title),
      scrollable: true,
      content: SizedBox(
        width: phone ? double.infinity : 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tooLong)
              Text(
                'Too long for a single QR code (${value.length} characters). '
                'Copy it instead.',
                style: AppTypography.body.copyWith(color: s.inkSecondary),
                textAlign: TextAlign.center,
              )
            else
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: s.edge),
                ),
                child: SizedBox.square(
                  dimension: side,
                  child: QrImageView(
                    key: ValueKey<String>(value),
                    data: value,
                    version: QrVersions.auto,
                    size: side,
                    padding: EdgeInsets.zero,
                    semanticsLabel: '$title QR code',
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            SelectableText(
              value,
              style: AppTypography.monoSmall.copyWith(color: s.inkSecondary),
              textAlign: TextAlign.center,
              maxLines: 4,
            ),
            if (caption case final c?) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                c,
                style: AppTypography.caption.copyWith(color: s.inkSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      actions: [
        // Closing is not what the sheet is for, so it is never the accent.
        if (phone)
          SecondaryButton(
            label: 'Close',
            isFullWidth: true,
            onPressed: () => Navigator.of(context).pop(),
          )
        else
          GhostButton(
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }
}

/// A 28 px icon button at a code box's edge (48 on touch): outlined 16 px
/// glyph in the secondary ink, the accent's under the pointer (both from
/// the themed [IconButton]). [color] overrides it for a glyph that states
/// something — the check of a copy that just happened.
class _EdgeIconButton extends StatelessWidget {
  const _EdgeIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final side = phone
        ? AppLayout.minTouchTarget
        : AppSpacing.controlHeightSmall;
    return IconButton(
      icon: Icon(icon, color: color),
      iconSize: phone ? AppSpacing.icon : AppSpacing.iconSmall,
      onPressed: onPressed,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: side, height: side),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
      ),
    );
  }
}

/// The copy control: a copy glyph that becomes a check for [_copiedFor].
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.value});

  final String value;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(_copiedFor);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) => _EdgeIconButton(
    icon: _copied ? Icons.check : Icons.copy_outlined,
    // The check is a fact — it was copied — so it is the success green.
    color: _copied ? AppScheme.of(context).success : null,
    tooltip: _copied ? 'Copied' : 'Copy',
    onPressed: _copy,
  );
}

/// The QR control beside a copy control: same size, same ink, so the two
/// read as one pair of ways to hand a value over.
class _QrButton extends StatelessWidget {
  const _QrButton({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => _EdgeIconButton(
    icon: Icons.qr_code_2_outlined,
    tooltip: 'Show QR',
    onPressed: () => showValueQr(context, title: title, value: value),
  );
}

/// The recess a value is printed in.
BoxDecoration _wellDecoration(AppScheme s) => BoxDecoration(
  color: s.well,
  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
  border: Border.all(color: s.edge),
);

/// A boxed, selectable, copyable monospace value (descriptor, txid, PSBT).
///
/// The value is clipped at [maxLines]. On a phone, when it does not fit, a
/// "Show all" toggle appears under it — a descriptor the user cannot read to
/// the end is one they cannot verify before copying.
class CodeBox extends StatefulWidget {
  const CodeBox({
    super.key,
    required this.value,
    this.label,
    this.maxLines = 4,
    this.showQr = false,
  });

  final String value;
  final String? label;
  final int maxLines;

  /// A QR control beside the copy control, opening [showValueQr]. Off by
  /// default: a PSBT or a whole descriptor bundle is too long for one code
  /// and has its own animated route.
  final bool showQr;

  @override
  State<CodeBox> createState() => _CodeBoxState();
}

class _CodeBoxState extends State<CodeBox> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final s = AppScheme.of(context);
    final textStyle = AppTypography.mono.copyWith(color: s.ink);

    final Widget text;
    if (phone) {
      text = LayoutBuilder(
        builder: (ctx, c) {
          // Does the value fit the cap? Measured, not guessed, so the toggle
          // only appears when something is actually hidden.
          final painter = TextPainter(
            text: TextSpan(text: widget.value, style: textStyle),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(ctx),
            maxLines: widget.maxLines,
          )..layout(maxWidth: c.maxWidth);
          final overflows = painter.didExceedMaxLines;
          painter.dispose();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                widget.value,
                style: textStyle,
                minLines: 1,
                maxLines: _expanded ? null : widget.maxLines,
              ),
              if (overflows)
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    foregroundColor: s.ink,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, AppLayout.minTouchTarget),
                    textStyle: AppTypography.label,
                  ),
                  child: Text(_expanded ? 'Show less' : 'Show all'),
                ),
            ],
          );
        },
      );
    } else {
      // minLines: without it a selectable text reserves every one of its
      // maxLines, and a one-line address sits in a four-line box.
      text = SelectableText(
        widget.value,
        style: textStyle,
        minLines: 1,
        maxLines: widget.maxLines,
      );
    }

    final title = widget.label ?? 'QR code';
    final controls = <Widget>[
      _CopyButton(value: widget.value),
      if (widget.showQr) _QrButton(title: title, value: widget.value),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              widget.label!,
              style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
            ),
          ),
        Container(
          width: double.infinity,
          // The controls sit in the corner: less padding on that side so
          // their hit area, not their glyph, meets the edge.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
          ),
          decoration: _wellDecoration(s),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: text),
              const SizedBox(width: AppSpacing.xs),
              // Stacked on a phone, side by side on desktop: two 48 dp
              // buttons in a row would eat a quarter of a 360 dp box. Lifted
              // so the first control centres on the value's first line.
              Transform.translate(
                offset: Offset(0, phone ? -AppSpacing.md : -AppSpacing.xs),
                child: phone
                    ? Column(mainAxisSize: MainAxisSize.min, children: controls)
                    : Row(mainAxisSize: MainAxisSize.min, children: controls),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Label, value and its copy control on one line.
///
/// Desktop keeps the 160 dp key column with the value in a well beside it.
/// On a phone the label sits above the well, the value wraps across the full
/// width (or, with [singleLine], collapses in the middle to fit one line) and
/// the controls are 48 dp.
class CopyRow extends StatelessWidget {
  const CopyRow({
    super.key,
    required this.label,
    required this.value,
    this.mono = true,
    this.singleLine = false,
    this.showQr = false,
  });

  final String label;
  final String value;
  final bool mono;

  /// A QR control beside the copy control, opening [showValueQr].
  final bool showQr;

  /// Phone only: keep the value on one line, middle-ellipsised to the width,
  /// instead of wrapping. Desktop already ellipsises at the end.
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final valueStyle = (mono ? AppTypography.mono : AppTypography.body)
        .copyWith(color: s.ink);
    final controls = <Widget>[
      _CopyButton(value: value),
      if (showQr) _QrButton(title: label, value: value),
    ];

    if (AppLayout.isPhone(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              decoration: _wellDecoration(s),
              child: Row(
                children: [
                  Expanded(
                    child: singleLine
                        ? MiddleEllipsisText(value, style: valueStyle)
                        : Text(
                            value,
                            style: valueStyle,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  ...controls,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: AppTypography.label.copyWith(color: s.inkSecondary),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.xs,
              ),
              constraints: const BoxConstraints(
                minHeight: AppSpacing.controlHeight,
              ),
              decoration: _wellDecoration(s),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: valueStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ...controls,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

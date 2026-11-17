import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

// Banners (design.md, "Controls"): a `panelInset` block, radius 8, a 16 px
// glyph in the status colour and the text in the primary ink. The status is
// told by the glyph and its words — never by a tinted background or a
// coloured border.

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.icon,
    required this.iconColor,
    this.title,
    this.action,
    this.copyable = false,
  });

  final String message;
  final IconData icon;
  final Color iconColor;
  final String? title;
  final Widget? action;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final t = title;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: s.panelInset,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nudged onto the first line's centre (20 line, 16 glyph).
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: AppSpacing.iconSmall, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t != null) ...[
                  Text(t, style: AppTypography.label.copyWith(color: s.ink)),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  message,
                  style:
                      (t != null ? AppTypography.caption : AppTypography.body)
                          .copyWith(color: s.ink),
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  action!,
                ],
              ],
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: AppSpacing.sm),
            _CopyButton(text: message),
          ],
        ],
      ),
    );
  }
}

/// Copies the banner text; the glyph turns into a check for a moment. A
/// small target on desktop; on a phone the same glyph centred in a 48 dp
/// square so the error can actually be grabbed.
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final icon = AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.quick),
      switchInCurve: AppMotion.settle,
      child: Icon(
        _copied ? Icons.check_outlined : Icons.copy_outlined,
        key: ValueKey(_copied),
        size: phone ? 20 : AppSpacing.iconSmall,
        color: _copied ? s.success : s.inkSecondary,
      ),
    );
    return Tooltip(
      message: _copied ? 'Copied' : 'Copy error',
      child: InkWell(
        onTap: _copy,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        hoverColor: s.hover,
        highlightColor: s.pressed,
        splashFactory: NoSplash.splashFactory,
        child: phone
            ? SizedBox.square(
                dimension: AppLayout.minTouchTarget,
                child: Center(child: icon),
              )
            : Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: icon,
              ),
      ),
    );
  }
}

/// Something worth knowing: a glyph in the secondary ink.
class InfoBanner extends StatelessWidget {
  const InfoBanner({super.key, required this.message, this.title, this.action});
  final String message;
  final String? title;

  /// A ghost or secondary button under the text.
  final Widget? action;

  @override
  Widget build(BuildContext context) => _Banner(
    message: message,
    title: title,
    action: action,
    icon: Icons.info_outlined,
    iconColor: AppScheme.of(context).inkSecondary,
  );
}

/// Something that may cost the user: a glyph in the warning ink.
class WarningBanner extends StatelessWidget {
  const WarningBanner({
    super.key,
    required this.message,
    this.title,
    this.action,
  });
  final String message;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => _Banner(
    message: message,
    title: title,
    action: action,
    icon: Icons.warning_amber_outlined,
    iconColor: AppScheme.of(context).warning,
  );
}

/// Something failed or will be lost: a glyph in the danger ink, and the
/// message can be copied for a bug report.
class DangerBanner extends StatelessWidget {
  const DangerBanner({
    super.key,
    required this.message,
    this.title,
    this.action,
  });
  final String message;
  final String? title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => _Banner(
    message: message,
    title: title,
    action: action,
    icon: Icons.error_outline,
    iconColor: AppScheme.of(context).danger,
    copyable: true,
  );
}

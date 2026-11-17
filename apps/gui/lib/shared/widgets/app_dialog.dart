import 'package:flutter/material.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'live_edge.dart';

// Dialogs and sheets (design.md, "Controls"): what floats over the page.
//
// One material: the solid `panel`, radius 16, a hairline, `floatShadow`,
// over the `scrim`. The title is a `sectionTitle`, the body is `body` in the
// secondary ink, the actions sit right-aligned at the foot (the quiet one
// first, the primary last). A phone gets a sheet where the desktop gets a
// dialog: same content, actions stacked full width with the primary on top.
// Things enter with a fade and an 8 px rise; nothing bounces.

/// The rise every dialog body makes as it enters, under the route's fade.
/// Runs once; skipped under reduced motion.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});
  final Widget child;

  static const double _rise = 8;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.emphasized,
      curve: AppMotion.settle,
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, _rise * (1 - t)),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

/// The dialog frame shared by [PromptDialog] and [AppDialog] on desktop.
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.content,
    this.title,
    this.icon,
    this.actions = const [],
    this.width,
    this.scrollable = false,
    this.contentPadding,
    this.actionsAlignment,
    this.shape,
    this.backgroundColor,
    this.titleTextStyle,
    this.contentTextStyle,
    this.edge = LiveEdgeMode.off,
    this.edgeColor,
    this.maxWidth = 560,
  });

  final Widget? title;
  final Widget? icon;
  final Widget content;
  final List<Widget> actions;

  /// See [AppDialog.edge].
  final LiveEdgeMode edge;
  final Color? edgeColor;

  /// The widest a content-sized dialog grows (see [AppDialog.maxWidth]).
  final double maxWidth;

  /// Fixed width; null sizes to the content between 280 and 560, the way an
  /// AlertDialog does.
  final double? width;
  final bool scrollable;
  final EdgeInsetsGeometry? contentPadding;
  final MainAxisAlignment? actionsAlignment;
  final ShapeBorder? shape;
  final Color? backgroundColor;
  final TextStyle? titleTextStyle;
  final TextStyle? contentTextStyle;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final hasTitle = title != null || icon != null;

    final head = !hasTitle
        ? null
        : Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xl,
              AppSpacing.xl,
              0,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  IconTheme.merge(
                    data: IconThemeData(
                      color: s.inkSecondary,
                      size: AppSpacing.icon,
                    ),
                    child: icon!,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                if (title != null)
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style:
                          titleTextStyle ??
                          AppTypography.sectionTitle.copyWith(color: s.ink),
                      child: title!,
                    ),
                  ),
              ],
            ),
          );

    Widget body = Padding(
      padding:
          contentPadding ??
          EdgeInsets.fromLTRB(
            AppSpacing.xl,
            hasTitle ? AppSpacing.lg : AppSpacing.xl,
            AppSpacing.xl,
            0,
          ),
      child: DefaultTextStyle.merge(
        style:
            contentTextStyle ??
            AppTypography.body.copyWith(color: s.inkSecondary),
        child: content,
      ),
    );
    if (scrollable) body = SingleChildScrollView(child: body);

    final foot = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        actions.isEmpty ? 0 : AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: actions.isEmpty
          ? null
          : OverflowBar(
              alignment: actionsAlignment ?? MainAxisAlignment.end,
              spacing: AppSpacing.sm,
              overflowSpacing: AppSpacing.sm,
              overflowAlignment: OverflowBarAlignment.end,
              children: actions,
            ),
    );

    Widget frame = Container(
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: backgroundColor ?? s.panel,
        shape:
            shape ??
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              side: BorderSide(color: s.edge),
            ),
        shadows: s.floatShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?head,
          Flexible(child: body),
          foot,
        ],
      ),
    );

    // What is happening to what the dialog shows, drawn over its own edge.
    frame = LiveEdge(
      mode: edge,
      color: edgeColor ?? s.success,
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      width: 2,
      child: frame,
    );

    frame = width != null
        ? SizedBox(width: width, child: frame)
        : IntrinsicWidth(
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: 280, maxWidth: maxWidth),
              child: frame,
            ),
          );

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      child: _Entrance(child: frame),
    );
  }
}

/// A dialog with a title, a body and actions — the password prompts and
/// every small decision. On a phone, opened through [showAppDialog], it
/// draws itself as an [AppSheet].
class PromptDialog extends StatelessWidget {
  const PromptDialog({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.icon,
    this.width = 380,
  });

  final String title;
  final Widget child;

  /// Quiet action first, the primary last.
  final List<Widget> actions;

  /// A glyph before the title, in the secondary ink.
  final IconData? icon;
  final double width;

  @override
  Widget build(BuildContext context) {
    final i = icon;
    if (_rendersAsSheet(context)) {
      return AppSheet(
        icon: i,
        title: Text(title),
        actions: actions,
        child: child,
      );
    }
    return _DialogFrame(
      title: Text(title),
      icon: i == null ? null : Icon(i),
      width: width,
      actions: actions,
      content: child,
    );
  }
}

/// The password field of the app's prompts: a normal field with its label as
/// an `eyebrow` above it and an eye to show or hide what was typed.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.autofocus = false,
    this.errorText,
    this.onSubmitted,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final String? errorText;
  final VoidCallback? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        // The label above is the field's name for assistive tech too.
        Semantics(
          label: widget.label,
          child: TextField(
            controller: widget.controller,
            obscureText: _obscure,
            autofocus: widget.autofocus,
            onSubmitted: (_) => widget.onSubmitted?.call(),
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              errorText: widget.errorText,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: phone ? 20 : AppSpacing.icon,
                  color: s.inkSecondary,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
                tooltip: _obscure ? 'Show' : 'Hide',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Adaptive dialog / sheet ───────────────────────────────────────────────────

/// True when the widget at [context] should draw itself as a bottom-sheet
/// body: a phone AND a route that actually anchors to the bottom (the one
/// [showAppDialog] opens). A PromptDialog or AppDialog that some caller still
/// opens through plain `showDialog` keeps its dialog frame — a sheet body
/// inside a dialog route would be laid out as a full-height panel pinned to
/// the top of the screen.
bool _rendersAsSheet(BuildContext context) =>
    AppLayout.isPhone(context) &&
    ModalRoute.of(context) is ModalBottomSheetRoute;

/// Opens a dialog the way the window expects: [showDialog] on desktop, a
/// modal bottom sheet on a phone ([AppLayout.isPhone]). Use it in place of
/// every `showDialog` call; the builder's widget should be a [PromptDialog] or
/// an [AppDialog] — both render themselves as a sheet body on a phone. The
/// sheet rises above the keyboard and respects the bottom inset.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final s = AppScheme.of(context);
  if (!AppLayout.isPhone(context)) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: s.scrim,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      builder: builder,
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    isDismissible: barrierDismissible,
    enableDrag: barrierDismissible,
    backgroundColor: Colors.transparent,
    barrierColor: s.scrim,
    sheetAnimationStyle: AnimationStyle(
      duration: AppMotion.of(context, AppMotion.emphasized),
      curve: AppMotion.settle,
      reverseDuration: AppMotion.of(context, AppMotion.standard),
      reverseCurve: AppMotion.exit,
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: builder(ctx),
    ),
  );
}

/// The app's dialog on desktop, an [AppSheet] on a phone — the AlertDialog
/// API (`title`, `content`, `actions`, …), so converting a call site is a
/// class rename plus `showDialog` → [showAppDialog].
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.icon,
    this.scrollable = false,
    this.contentPadding,
    this.actionsAlignment,
    this.shape,
    this.backgroundColor,
    this.titleTextStyle,
    this.contentTextStyle,
    this.edge = LiveEdgeMode.off,
    this.edgeColor,
    this.maxWidth = 560,
  });

  final Widget? title;
  final Widget? content;

  /// The widest the dialog grows around its content on desktop, padding
  /// included. 560 holds a form or a transaction's detail; a dialog that
  /// shows two things side by side asks for more.
  final double maxWidth;

  /// Quiet action first, the primary last.
  final List<Widget>? actions;

  /// The dialog's live edge ([LiveEdge]): `working` while the app signs or
  /// broadcasts what the dialog shows, `done` once it landed. Off by
  /// default — a dialog's edge is a hairline.
  final LiveEdgeMode edge;

  /// The hue of [edge]; the success green when null.
  final Color? edgeColor;

  /// A glyph before the title, in the secondary ink.
  final Widget? icon;
  final bool scrollable;
  final EdgeInsetsGeometry? contentPadding;
  final MainAxisAlignment? actionsAlignment;
  final ShapeBorder? shape;
  final Color? backgroundColor;
  final TextStyle? titleTextStyle;
  final TextStyle? contentTextStyle;

  @override
  Widget build(BuildContext context) {
    if (!_rendersAsSheet(context)) {
      return _DialogFrame(
        title: title,
        icon: icon,
        content: content ?? const SizedBox.shrink(),
        actions: actions ?? const [],
        scrollable: scrollable,
        contentPadding: contentPadding,
        actionsAlignment: actionsAlignment,
        shape: shape,
        backgroundColor: backgroundColor,
        titleTextStyle: titleTextStyle,
        contentTextStyle: contentTextStyle,
        edge: edge,
        edgeColor: edgeColor,
        maxWidth: maxWidth,
      );
    }
    return AppSheet(
      title: title,
      leading: icon,
      actions: actions ?? const [],
      edge: edge,
      edgeColor: edgeColor,
      child: content ?? const SizedBox.shrink(),
    );
  }
}

/// Bottom-sheet body used on phones wherever desktop shows a dialog: a
/// grabber, an optional icon/title row, the content in its own scroll view
/// (capped at 90% of the screen so the grabber stays reachable) and the
/// actions stacked full width at the foot, the primary on top where the
/// thumb lands.
///
/// Pair with `showModalBottomSheet(isScrollControlled: true,
/// backgroundColor: Colors.transparent, useSafeArea: true)` — or simply
/// [showAppDialog], which does exactly that on a phone.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.leading,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    this.edge = LiveEdgeMode.off,
    this.edgeColor,
  });

  final Widget child;
  final Widget? title;

  /// See [AppDialog.edge].
  final LiveEdgeMode edge;
  final Color? edgeColor;

  /// A glyph before the title, in the secondary ink. [leading] wins when
  /// both are given (it is the AlertDialog `icon` slot, any widget).
  final IconData? icon;
  final Widget? leading;

  /// In dialog order — the quiet action first, the primary last. The sheet
  /// stacks them reversed, so the primary is on top.
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;
    final glyph =
        leading ?? (icon == null ? null : Icon(icon, size: AppSpacing.icon));
    Widget? head;
    if (title != null || glyph != null) {
      head = Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            if (glyph != null) ...[
              IconTheme.merge(
                data: IconThemeData(color: s.inkSecondary, size: 20),
                child: glyph,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            if (title != null)
              Expanded(
                child: DefaultTextStyle.merge(
                  style: AppTypography.sectionTitle.copyWith(color: s.ink),
                  child: title!,
                ),
              ),
          ],
        ),
      );
    }
    final stacked = actions.reversed.toList();
    const corners = BorderRadius.vertical(
      top: Radius.circular(AppSpacing.radiusXl),
    );
    return SafeArea(
      top: false,
      child: LiveEdge(
        mode: edge,
        color: edgeColor ?? s.success,
        borderRadius: corners,
        width: 2,
        child: _sheetBody(context, s, maxHeight, corners, head, stacked),
      ),
    );
  }

  Widget _sheetBody(
    BuildContext context,
    AppScheme s,
    double maxHeight,
    BorderRadius corners,
    Widget? head,
    List<Widget> stacked,
  ) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: corners,
        border: Border.all(color: s.edge),
        boxShadow: s.floatShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: AppSpacing.xxl,
              height: AppSpacing.xs,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: s.edgeStrong,
                borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              ),
            ),
          ),
          ?head,
          Flexible(
            child: SingleChildScrollView(
              padding: padding,
              child: DefaultTextStyle.merge(
                style: AppTypography.bodyOf(
                  context,
                ).copyWith(color: s.inkSecondary),
                child: child,
              ),
            ),
          ),
          if (stacked.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < stacked.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.sm),
                    stacked[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

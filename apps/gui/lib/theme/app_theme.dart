import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_motion.dart';
import 'app_scheme.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Material's defaults, brought into the design system: every raw
/// `TextField`, `TextButton`, dialog, menu, switch and tooltip the app draws
/// takes its surface, hairline, radius and type from here, so a widget that
/// was never wrapped in a kit component still belongs.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  // ── The phone overlay ─────────────────────────────────────────────────────
  //
  // [_build] is context-free — one ThemeData for every platform — so the
  // phone's controls are laid over the resolved theme instead, from
  // `MaterialApp(builder: AppTheme.phoneBuilder)`. Every route, dialog and
  // sheet is a descendant of what the builder wraps, so one wiring line
  // reaches every field and every raw Material button in the app. Off a
  // phone it returns the child untouched, so desktop renders exactly the
  // theme above.

  /// Wire as `MaterialApp(builder: AppTheme.phoneBuilder)`.
  static Widget phoneBuilder(BuildContext context, Widget? child) {
    final c = child ?? const SizedBox.shrink();
    if (!AppLayout.isPhone(context)) return c;
    return Theme(data: _phone(context), child: c);
  }

  static OutlineInputBorder _field(double radius, BorderSide side) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: side,
      );

  static ThemeData _phone(BuildContext context) {
    final base = Theme.of(context);
    final s = AppScheme.of(context);
    const r = AppSpacing.radiusPhoneControl;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(r),
    );
    const tall = Size(64.0, AppSpacing.phoneControlHeight);
    final label = WidgetStatePropertyAll(AppTypography.buttonOf(context));
    ButtonStyle slab(ButtonStyle? style) =>
        (style ?? const ButtonStyle()).copyWith(
          minimumSize: const WidgetStatePropertyAll(tall),
          shape: WidgetStatePropertyAll(shape),
          textStyle: label,
        );
    return base.copyWith(
      iconTheme: base.iconTheme.copyWith(size: 22),
      // Fields: filled, no border at rest, a neutral ring on focus.
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        constraints: const BoxConstraints(
          minHeight: AppSpacing.phoneFieldHeight,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        isDense: false,
        border: _field(r, BorderSide.none),
        enabledBorder: _field(r, BorderSide.none),
        disabledBorder: _field(r, BorderSide.none),
        focusedBorder: _field(r, BorderSide(color: s.focus, width: 1.5)),
        errorBorder: _field(r, BorderSide(color: s.danger, width: 1.5)),
        focusedErrorBorder: _field(r, BorderSide(color: s.danger, width: 1.5)),
        hintStyle: AppTypography.bodyLarge.copyWith(color: s.inkFaint),
      ),
      textTheme: base.textTheme.copyWith(
        bodyLarge: AppTypography.bodyLarge.copyWith(color: s.ink),
        titleMedium: AppTypography.bodyLarge.copyWith(color: s.ink),
      ),
      // The raw Material buttons a dialog draws take the same slab as the
      // design-system ones, so an action never sits shorter than its
      // neighbour.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: slab(base.elevatedButtonTheme.style),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: slab(base.filledButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: slab(base.textButtonTheme.style),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: slab(base.outlinedButtonTheme.style),
      ),
    );
  }

  static ThemeData _build(Brightness brightness) {
    final s = AppScheme.forBrightness(brightness);
    final isDark = s.isDark;
    const rControl = AppSpacing.radiusMd;
    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(rControl),
    );
    const controlPadding = EdgeInsets.symmetric(horizontal: AppSpacing.lg);
    const controlSize = Size(64, AppSpacing.controlHeight);

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: s.accent,
      onPrimary: s.onAccent,
      secondary: s.ink,
      onSecondary: s.canvas,
      surface: s.panel,
      onSurface: s.ink,
      onSurfaceVariant: s.inkSecondary,
      error: s.danger,
      onError: Colors.white,
      outline: s.edgeStrong,
      outlineVariant: s.edge,
      surfaceTint: Colors.transparent,
      surfaceContainerLowest: s.chrome,
      surfaceContainerLow: s.canvas,
      surfaceContainer: s.panel,
      surfaceContainerHigh: s.panelInset,
      surfaceContainerHighest: s.panelInset,
      scrim: Colors.black,
    );

    final text =
        GoogleFonts.ibmPlexSansTextTheme(
              isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
            )
            .apply(bodyColor: s.ink, displayColor: s.ink)
            .copyWith(
              bodyLarge: AppTypography.body.copyWith(color: s.ink),
              bodyMedium: AppTypography.body.copyWith(color: s.ink),
              bodySmall: AppTypography.caption.copyWith(color: s.inkSecondary),
              titleLarge: AppTypography.sectionTitle.copyWith(color: s.ink),
              titleMedium: AppTypography.body.copyWith(color: s.ink),
              titleSmall: AppTypography.label.copyWith(color: s.ink),
              labelLarge: AppTypography.button.copyWith(color: s.ink),
              labelMedium: AppTypography.eyebrow.copyWith(
                color: s.inkSecondary,
              ),
              labelSmall: AppTypography.eyebrow.copyWith(color: s.inkFaint),
            );

    // One state layer for everything Material tints on hover and press.
    final overlay = WidgetStateProperty.resolveWith<Color?>((states) {
      if (states.contains(WidgetState.pressed)) return s.pressed;
      if (states.contains(WidgetState.hovered)) return s.hover;
      if (states.contains(WidgetState.focused)) return s.hover;
      return Colors.transparent;
    });

    OutlineInputBorder field(BorderSide side) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(rControl),
      borderSide: side,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      // A hover is a surface step and a press is a deeper one; no ripple
      // spreads across a row.
      splashFactory: NoSplash.splashFactory,
      hoverColor: s.hover,
      highlightColor: s.pressed,
      focusColor: s.hover,
      splashColor: Colors.transparent,
      // Pages fade in, fast, on every platform — never slide in from the side.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.macOS: FadePageTransitionsBuilder(),
          TargetPlatform.windows: FadePageTransitionsBuilder(),
          TargetPlatform.linux: FadePageTransitionsBuilder(),
          TargetPlatform.android: FadePageTransitionsBuilder(),
          TargetPlatform.iOS: FadePageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadePageTransitionsBuilder(),
        },
      ),
      fontFamily: GoogleFonts.ibmPlexSans().fontFamily,
      textTheme: text,
      iconTheme: IconThemeData(color: s.inkSecondary, size: AppSpacing.icon),
      scaffoldBackgroundColor: s.canvas,
      canvasColor: s.canvas,
      cardTheme: CardThemeData(
        color: s.panel,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: s.edge),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: s.edge, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.panelInset,
        isDense: true,
        hintStyle: AppTypography.body.copyWith(color: s.inkFaint),
        labelStyle: AppTypography.body.copyWith(color: s.inkSecondary),
        floatingLabelStyle: AppTypography.label.copyWith(color: s.inkSecondary),
        helperStyle: AppTypography.caption.copyWith(color: s.inkFaint),
        errorStyle: AppTypography.caption.copyWith(color: s.danger),
        prefixIconColor: s.inkFaint,
        suffixIconColor: s.inkFaint,
        border: field(BorderSide(color: s.edge)),
        enabledBorder: field(BorderSide(color: s.edge)),
        disabledBorder: field(BorderSide(color: s.edge)),
        focusedBorder: field(BorderSide(color: s.focus, width: 1.5)),
        errorBorder: field(BorderSide(color: s.danger)),
        focusedErrorBorder: field(BorderSide(color: s.danger, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
      ),
      // Where the user types is theirs: the caret and the selection take
      // the accent (design.md, "The accent"). The field's focus ring stays
      // neutral — a red ring is an error.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: s.accent,
        selectionColor: s.accent.withValues(alpha: isDark ? 0.42 : 0.24),
        selectionHandleColor: s.accent,
      ),
      // The one filled accent control. Everything beside it is neutral.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: s.accent,
          foregroundColor: s.onAccent,
          disabledBackgroundColor: s.panelInset,
          disabledForegroundColor: s.inkFaint,
          elevation: 0,
          shadowColor: Colors.transparent,
          minimumSize: controlSize,
          padding: controlPadding,
          shape: controlShape,
          textStyle: AppTypography.button,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: s.accent,
          foregroundColor: s.onAccent,
          disabledBackgroundColor: s.panelInset,
          disabledForegroundColor: s.inkFaint,
          minimumSize: controlSize,
          padding: controlPadding,
          shape: controlShape,
          textStyle: AppTypography.button,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: s.ink,
          backgroundColor: s.panelInset,
          side: BorderSide(color: s.edge),
          minimumSize: controlSize,
          padding: controlPadding,
          shape: controlShape,
          textStyle: AppTypography.button,
        ).copyWith(overlayColor: overlay),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: s.ink,
          minimumSize: controlSize,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: controlShape,
          textStyle: AppTypography.button,
        ).copyWith(overlayColor: overlay),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return s.inkFaint.withValues(alpha: 0.5);
            }
            // Under the pointer an icon control takes the accent's glyph
            // colour: the wallet's own, on the thing about to be used.
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return s.accentGlyph;
            }
            return s.inkSecondary;
          }),
          overlayColor: overlay,
          iconSize: const WidgetStatePropertyAll(AppSpacing.icon),
          shape: WidgetStatePropertyAll(controlShape),
        ),
      ),
      switchTheme: SwitchThemeData(
        // On is the ink, not the accent: a row of red switches reads as a
        // row of alarms.
        thumbColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.canvas : s.inkFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.ink : s.panelInset,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? Colors.transparent
              : s.edgeStrong,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(1),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      // A tick is the user's own mark, so it is the accent; an untouched
      // box is an outline.
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((st) {
          if (!st.contains(WidgetState.selected)) return Colors.transparent;
          return st.contains(WidgetState.disabled) ? s.edgeStrong : s.accent;
        }),
        checkColor: WidgetStatePropertyAll(s.onAccent),
        side: WidgetStateBorderSide.resolveWith(
          (st) => BorderSide(
            color:
                st.contains(WidgetState.selected) &&
                    !st.contains(WidgetState.disabled)
                ? s.accent
                : s.edgeStrong,
            width: 1.5,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        ),
        overlayColor: overlay,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.accent : s.edgeStrong,
        ),
        overlayColor: overlay,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        // A spinner is the app working for this wallet: its colour.
        color: s.accentGlyph,
        linearTrackColor: s.edge,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: s.ink,
        inactiveTrackColor: s.edgeStrong,
        thumbColor: s.ink,
        overlayColor: s.hover,
        trackHeight: 2,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 500),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        textStyle: AppTypography.eyebrow.copyWith(color: s.ink),
        decoration: BoxDecoration(
          color: s.panelInset,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: s.edge),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: s.scrim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          side: BorderSide(color: s.edge),
        ),
        titleTextStyle: AppTypography.sectionTitle.copyWith(color: s.ink),
        contentTextStyle: AppTypography.body.copyWith(color: s.inkSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.panel,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: s.scrim,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: s.panel,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: s.edge),
        ),
        textStyle: AppTypography.body.copyWith(color: s.ink),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(s.panel),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              side: BorderSide(color: s.edge),
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.panelInset,
        contentTextStyle: AppTypography.body.copyWith(color: s.ink),
        actionTextColor: s.ink,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          side: BorderSide(color: s.edge),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: s.inkSecondary,
        textColor: s.ink,
        titleTextStyle: AppTypography.body.copyWith(color: s.ink),
        subtitleTextStyle: AppTypography.caption.copyWith(
          color: s.inkSecondary,
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStateProperty.resolveWith(
          (st) => s.ink.withValues(
            alpha: st.contains(WidgetState.hovered) ? 0.32 : 0.16,
          ),
        ),
      ),
    );
  }
}

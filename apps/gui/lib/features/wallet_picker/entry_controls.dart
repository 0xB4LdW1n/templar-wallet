import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';

// The two controls the entry screens (Welcome, the wallet picker) carry in
// their top bar before any wallet is open: the theme switch and, on the
// picker, the storage lock. Same body as the design-system buttons — a
// hairline outline, a hover layer, a 2 px focus ring — at icon size.

/// An outlined square icon button with a tooltip. 44 on desktop — these sit
/// beside the product mark on an otherwise empty bar, and a 36 px control
/// there reads as a speck — and the 48 dp touch floor on a phone; the glyph
/// is the secondary ink.
class EntryIconButton extends StatefulWidget {
  const EntryIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<EntryIconButton> createState() => _EntryIconButtonState();
}

class _EntryIconButtonState extends State<EntryIconButton> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final side = phone ? AppLayout.minTouchTarget : 44.0;
    const radius = AppSpacing.radiusPhoneControl;
    final fill = _down
        ? s.pressed
        : _hover
        ? s.hover
        : Colors.transparent;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        excludeSemantics: true,
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
                widget.onPressed();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.instant),
              curve: AppMotion.settle,
              width: side,
              height: side,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: _hover ? s.edgeStrong : s.edge),
              ),
              foregroundDecoration: _focus
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: s.focus, width: 2),
                    )
                  : null,
              child: Icon(
                widget.icon,
                size: AppSpacing.navIcon,
                color: _hover ? s.ink : s.inkSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dark / light switch for the screens outside a wallet. The glyph names the
/// mode it switches to.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark =
        context.select<AppState, ThemeMode>((st) => st.themeMode) ==
        ThemeMode.dark;
    return EntryIconButton(
      icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      tooltip: dark ? 'Light mode' : 'Dark mode',
      onPressed: context.read<AppState>().toggleTheme,
    );
  }
}

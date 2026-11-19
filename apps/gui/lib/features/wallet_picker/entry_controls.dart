import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../settings/liquid_network_switch.dart';

// The controls the entry screens (Welcome, the wallet picker) carry before
// any wallet is open: the theme switch, the Tor switch and, on the picker,
// the storage lock and the network. Same body as the design-system buttons —
// a hairline outline, a hover layer, a 2 px focus ring — at icon size.

/// The outlined body every entry control shares. 44 tall on desktop — these
/// sit on an otherwise empty bar, and a 36 px control there reads as a speck
/// — and the 48 dp touch floor on a phone. Square unless [square] is false,
/// then as wide as its content plus side padding.
class _EntryControl extends StatefulWidget {
  const _EntryControl({
    required this.tooltip,
    required this.onPressed,
    required this.builder,
    this.square = true,
  });

  final String tooltip;

  /// Null draws the control dimmed and inert (the tooltip says why).
  final VoidCallback? onPressed;

  /// The content, in the ink the control's state calls for.
  final Widget Function(Color ink) builder;

  final bool square;

  @override
  State<_EntryControl> createState() => _EntryControlState();
}

class _EntryControlState extends State<_EntryControl> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final side = phone ? AppLayout.minTouchTarget : 44.0;
    const radius = AppSpacing.radiusPhoneControl;
    final enabled = widget.onPressed != null;
    final lit = enabled && _hover;
    final fill = enabled && _down
        ? s.pressed
        : lit
        ? s.hover
        : Colors.transparent;
    final ink = !enabled
        ? s.inkFaint
        : lit
        ? s.ink
        : s.inkSecondary;

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.tooltip,
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
                widget.onPressed?.call();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapUp: enabled ? (_) => setState(() => _down = false) : null,
            onTapCancel: enabled ? () => setState(() => _down = false) : null,
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.instant),
              curve: AppMotion.settle,
              width: widget.square ? side : null,
              height: side,
              padding: widget.square
                  ? null
                  : const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: lit ? s.edgeStrong : s.edge),
              ),
              foregroundDecoration: _focus
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: s.focus, width: 2),
                    )
                  : null,
              child: widget.builder(ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// An outlined square icon button with a tooltip; the glyph is the
/// secondary ink, the primary under the pointer.
class EntryIconButton extends StatelessWidget {
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
  Widget build(BuildContext context) => _EntryControl(
    tooltip: tooltip,
    onPressed: onPressed,
    builder: (ink) => Icon(icon, size: AppSpacing.navIcon, color: ink),
  );
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

/// Tor, the Tor Project's glyph in the control's ink. A placeholder: the
/// engine has no Tor transport yet, so a tap only says so.
class TorButton extends StatelessWidget {
  const TorButton({super.key});

  static const String _glyph = 'assets/images/tor.svg';

  @override
  Widget build(BuildContext context) => _EntryControl(
    tooltip: 'Tor (coming soon)',
    onPressed: () => ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Connecting through Tor is not available yet.'),
        ),
      ),
    builder: (ink) => SvgPicture.asset(
      _glyph,
      width: AppSpacing.navIcon,
      height: AppSpacing.navIcon,
      colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
      excludeFromSemantics: true,
    ),
  );
}

/// The test network every wallet opens on — Testnet or Regtest — and the
/// switch between them, before a wallet is open.
///
/// It moves Liquid (and Bitcoin with it, when a test server is joined)
/// through [switchLiquidNetwork], the same confirmation and switch as
/// Settings › Network: Regtest is the joined test server's chains, or the
/// local Liquid regtest with the policy asset the engine knows. Joining a
/// test server stays in Settings, where its URL is entered.
class NetworkButton extends StatelessWidget {
  const NetworkButton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final st = context.watch<AppState>();
    final info = st.liquidNetwork;
    final regtest = st.isBitcoinRegtest || st.isLiquidRegtest;
    final locked = info?.envLocked ?? false;
    final label = regtest ? 'Regtest' : 'Testnet';

    Future<void> pick(String target) async {
      final now = info;
      if (now == null || target == now.shortName) return;
      try {
        await switchLiquidNetwork(
          context,
          target: target,
          // On a test server the engine takes the policy asset from it.
          policyAsset: now.testServer != null
              ? null
              : now.isRegtest
              ? now.policyAsset
              : now.regtestDefaultPolicyAsset,
        );
      } on LiquidNetworkSwitchError catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    final tooltip = locked
        ? 'TEMPLAR_LIQUID_NETWORK fixes the network for this session'
        : info == null
        ? 'Test networks only'
        : 'Test networks only · switch network';

    return MenuAnchor(
      alignmentOffset: const Offset(0, AppSpacing.xs),
      style: MenuStyle(backgroundColor: WidgetStatePropertyAll(s.panel)),
      menuChildren: [
        for (final (target, name, note) in const [
          ('testnet', 'Testnet', 'The public test networks'),
          ('regtest', 'Regtest', 'A test server or a local regtest'),
        ])
          MenuItemButton(
            onPressed: () => pick(target),
            trailingIcon: (target == 'regtest') == regtest
                ? Icon(Icons.check, size: 20, color: s.inkSecondary)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: AppTypography.body.copyWith(color: s.ink)),
                  Text(
                    note,
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
      builder: (context, menu, _) => _EntryControl(
        tooltip: tooltip,
        square: false,
        onPressed: locked || info == null
            ? null
            : () => menu.isOpen ? menu.close() : menu.open(),
        builder: (ink) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: s.testnet,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: AppTypography.label.copyWith(color: ink)),
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.unfold_more, size: AppSpacing.iconSmall, color: ink),
          ],
        ),
      ),
    );
  }
}

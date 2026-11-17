// Privacy mask — one switch that blanks every coin amount and fiat value on
// screen, for using the wallet in public.
//
// It is a *display* mask and nothing more: the amounts are still loaded, still
// used for fee maths, still exported. Anything that hides real numbers has to
// be obviously reversible, so the control is a single eye that shows its state
// (open = visible, struck-through = hidden) and lives next to the balance it
// covers rather than buried in Settings.
//
// It covers HOLDINGS — what you own: the net-worth hero, asset cards, coin
// amounts, activity rows. It deliberately does NOT cover the amount you are
// composing or about to sign (send wizard, swap legs, PSBT/PSET review). Those
// numbers are the thing being authorised; a wallet that lets you sign "••••••"
// has traded a shoulder-surfing risk for a spend-the-wrong-amount one.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_spacing.dart';

/// The stand-in for a masked number. Bullets, not a fixed-width blur: it reads
/// as "withheld" at a glance and never suggests a real digit count.
const String kMaskedAmount = '••••';

/// True when the privacy mask is on. Subscribes the caller to changes.
bool balancesHidden(BuildContext context) =>
    context.select<AppState, bool>((s) => s.balancesHidden);

/// [text] as it should be rendered right now — the value, or bullets while the
/// mask is on. Use for every amount, balance and fiat figure.
String maskAmount(BuildContext context, String text) =>
    balancesHidden(context) ? kMaskedAmount : text;

/// Nullable variant: a null value stays null (nothing to draw either way).
String? maskAmountOrNull(BuildContext context, String? text) =>
    text == null ? null : maskAmount(context, text);

/// A masked amount as a widget.
///
/// Prefer this over `Text(maskAmount(context, …))`: the lookup happens in this
/// widget's own `build`, so it is safe inside `AnimatedBuilder`/`LayoutBuilder`
/// callbacks, where calling `context.select` against the enclosing element
/// throws ("Tried to use `context.select` outside of the `build` method").
class Amount extends StatelessWidget {
  const Amount(
    this.text, {
    super.key,
    this.style,
    this.overflow,
    this.maxLines,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final TextOverflow? overflow;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
    maskAmount(context, text),
    style: style,
    overflow: overflow,
    maxLines: maxLines,
    textAlign: textAlign,
  );
}

/// The eye. Open when amounts are visible, struck through when they are
/// hidden — the icon always shows the *current* state, not the action, so the
/// screen can be read at a glance. A plain icon button in the secondary ink;
/// hidden is a state, not an alarm, so it never takes a colour of its own.
///
/// On a phone the hit area is a 48 dp square around a 22 px glyph; on desktop
/// a 28 px square around the 18 px chrome icon.
class PrivacyToggle extends StatelessWidget {
  const PrivacyToggle({super.key, this.color});

  /// Overrides the resolved ink colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final hidden = balancesHidden(context);
    final phone = AppLayout.isPhone(context);
    final side = phone
        ? AppLayout.minTouchTarget
        : AppSpacing.controlHeightSmall;

    return IconButton(
      tooltip: hidden ? 'Show amounts' : 'Hide amounts',
      onPressed: () => context.read<AppState>().toggleBalancesHidden(),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: side, height: side),
      iconSize: phone ? 22 : AppSpacing.icon,
      color: color,
      icon: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.quick),
        switchInCurve: AppMotion.settle,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: Icon(
          hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          key: ValueKey(hidden),
        ),
      ),
    );
  }
}

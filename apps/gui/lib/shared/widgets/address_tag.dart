// The mark of an address, drawn: its label as a small coloured rectangle,
// and the row of swatches its colour is picked from.
//
// An address's colour is data (design.md, "Colour as data"): grey until the
// user picks one, and then it says "this is that address" wherever it is
// listed: Receive, the coin wall's cards, the coin list, Send's own-address
// picker. Two coins that share an address share its colour. Applied the way
// every data hue is: a washed fill, a hairline in the hue, the words in ink.

import 'package:flutter/material.dart';

import '../../services/address_label_store.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The hue [address] is drawn in: the one the user picked, else grey. Read
/// under a listener of [AddressLabelStore].
Color addressHueOf(AppScheme s, String address) =>
    tagHue(s, AddressLabelStore.instance.hueFor(address));

/// The tag hue at [index] (wraps, so a stored index is always a colour).
Color tagHue(AppScheme s, int index) => s.series[index % s.series.length];

/// The fill of a tag in [hue]: stronger than a card's wash, because a tag
/// is a few words wide and has to be found at a glance.
Color tagFill(AppScheme s, Color hue) =>
    hue.withValues(alpha: s.isDark ? 0.34 : 0.2);

/// The hairline of a tag in [hue]: the hue itself, nearly whole.
Color tagEdge(AppScheme s, Color hue) =>
    hue.withValues(alpha: s.isDark ? 0.8 : 0.85);

/// An address's label as a tag: a small rectangle washed in the address's
/// colour with a hairline in it, the label in ink. Without a [hue] it is
/// the quiet iron tag. With [onTap] it is its own editor.
class AddressTag extends StatelessWidget {
  const AddressTag({
    super.key,
    required this.label,
    required this.hue,
    this.onTap,
    this.tooltip,
    this.mono = false,
  });

  /// The tag of [address] as the store has it, or null when the address has
  /// no label. Read under a listener of [AddressLabelStore].
  static Widget? of(
    BuildContext context,
    String address, {
    VoidCallback? onTap,
    String? fallbackLabel,
  }) {
    final label = AddressLabelStore.instance.labelFor(address) ?? fallbackLabel;
    if (label == null) return null;
    return AddressTag(
      label: label,
      hue: addressHueOf(AppScheme.of(context), address),
      onTap: onTap,
      tooltip: onTap == null ? null : 'Edit label',
    );
  }

  final String label;
  final Color? hue;
  final VoidCallback? onTap;
  final String? tooltip;

  /// Set the words in `monoSmall`: the tag holds an address, not a name.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final h = hue;
    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: h == null ? s.panelInset : tagFill(s, h),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        border: Border.all(color: h == null ? s.edge : tagEdge(s, h)),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: (mono ? AppTypography.monoSmall : AppTypography.eyebrow)
            .copyWith(color: s.ink),
      ),
    );
    return _tappable(context, tag, onTap: onTap, tooltip: tooltip);
  }
}

/// Where a label would be, on an address that has none: a dashed outline
/// saying so, and the way to write one — "this can be labelled", on screen
/// rather than behind an icon.
class AddAddressTag extends StatelessWidget {
  const AddAddressTag({super.key, required this.onTap, this.label = 'Label'});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final tag = CustomPaint(
      foregroundPainter: _DashedRect(color: s.edgeStrong),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: AppSpacing.md, color: s.inkSecondary),
            const SizedBox(width: 2),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
            ),
          ],
        ),
      ),
    );
    return _tappable(context, tag, onTap: onTap, tooltip: 'Add label');
  }
}

Widget _tappable(
  BuildContext context,
  Widget tag, {
  required VoidCallback? onTap,
  required String? tooltip,
}) {
  if (onTap == null) return tag;
  final phone = AppLayout.isPhone(context);
  final target = Semantics(
    button: true,
    label: tooltip,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Touch: the tag keeps its size and the target grows around it.
        child: phone
            ? ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppLayout.minTouchTarget,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: tag,
                ),
              )
            : tag,
      ),
    ),
  );
  if (tooltip == null || phone) return target;
  return Tooltip(message: tooltip, child: target);
}

/// A 3-on-3-off dashed rounded rectangle (radius 4).
class _DashedRect extends CustomPainter {
  const _DashedRect({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.5),
      const Radius.circular(AppSpacing.radiusXs),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final m in (Path()..addRRect(rrect)).computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 3), paint);
        d += 6;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRect old) => old.color != color;
}

/// The colour of an address with no label to print: a small square of it.
class AddressSwatch extends StatelessWidget {
  const AddressSwatch({super.key, required this.hue, this.size = 10});

  final Color hue;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: hue,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// The row of swatches a tag's colour is picked from: grey first — the
/// colour of an address nobody coloured — then the other tag hues in their
/// fixed order. The chosen one wears an ink ring with a gap, the way the
/// wallet's own colour does in Settings.
class TagHuePicker extends StatelessWidget {
  const TagHuePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Index into the tag hues, or null when none is chosen yet.
  final int? selected;
  final ValueChanged<int> onChanged;

  static const List<String> _names = [
    'Blue',
    'Violet',
    'Gold',
    'Rose',
    'Teal',
    'Grey',
  ];

  /// Grey leads: it is where every address starts.
  static const List<int> _order = [AddressLabelStore.greyHue, 0, 1, 2, 3, 4];

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return Wrap(
      spacing: phone ? 0 : AppSpacing.sm,
      children: [
        for (final i in _order)
          _HueSwatch(
            color: tagHue(s, i),
            name: _names[i % _names.length],
            selected: selected == i,
            onTap: () => onChanged(i),
          ),
      ],
    );
  }
}

class _HueSwatch extends StatefulWidget {
  const _HueSwatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_HueSwatch> createState() => _HueSwatchState();
}

class _HueSwatchState extends State<_HueSwatch> {
  bool _focus = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final cell = phone ? AppLayout.minTouchTarget : AppSpacing.xxl;
    final ring = widget.selected
        ? s.ink
        : _focus
        ? s.focus
        : _hover
        ? s.edgeStrong
        : Colors.transparent;
    final swatch = Semantics(
      button: true,
      selected: widget.selected,
      label: '${widget.name} tag colour',
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            width: cell,
            height: cell,
            child: Center(
              child: AnimatedContainer(
                duration: AppMotion.of(context, AppMotion.instant),
                curve: AppMotion.settle,
                width: AppSpacing.xl + AppSpacing.xs,
                height: AppSpacing.xl + AppSpacing.xs,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: ring, width: 2),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (phone) return swatch;
    return Tooltip(message: widget.name, child: swatch);
  }
}

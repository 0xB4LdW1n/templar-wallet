// Shared UTXO rendering widgets — used by the UTXO (coin control) screen and
// by the send wizard's manual input selection step, so picking coins looks
// and feels identical everywhere.
//
// The notes are one of the app's moments (design.md, "The moments"): every
// coin is a banknote printed in its size tier's hue — the paper washed with
// it, the edge and the engraving in it, the tier a word in it — while the
// amount stays ink. Every note is one height and the tier sets its length,
// so a row of notes lines up and a coin worth more is a longer piece of
// paper. Frozen and pending are states, not colours: they drain the note
// back to iron.
//
// In a list the same note is drawn in miniature at the head of the row —
// the same hue, the same five lengths — and the tier word and the share
// meter say it again, so the screen reads in greyscale.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../features/utxos/models/utxo.dart';
import '../../services/address_label_store.dart';
import '../../services/price_service.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../features/receive/address_dialogs.dart'
    show showAddressLabelPrompt;
import '../../features/utxos/utxo_wall.dart';
import 'address_tag.dart';
import 'asset_logo.dart';
import 'badges.dart';
import 'live_edge.dart';
import 'privacy.dart';
import 'segmented_switch.dart';
import 'utxo_details.dart';

/// State tag for a coin, or null when there is nothing worth saying.
///
/// "Available" is the default state of every coin on the screen, so a tag on
/// almost every row would bury the three states that actually change what
/// you can do with a coin. Dust is the only one with a status dot: it is a
/// warning about cost. Frozen carries the lock, pending the word.
(BadgeVariant, String, IconData?)? utxoStateBadge(UtxoState state) =>
    switch (state) {
      UtxoState.available => null,
      UtxoState.frozen => (BadgeVariant.neutral, 'Frozen', kFrozenIcon),
      UtxoState.dusty => (BadgeVariant.warning, 'Dust', null),
      UtxoState.unconfirmed => (BadgeVariant.neutral, 'Pending', null),
    };

/// The glyph a frozen coin wears — on its tag, in place of its checkbox.
const IconData kFrozenIcon = Icons.lock_outlined;

/// [StatusBadge] for [utxoStateBadge]'s record.
Widget utxoStateChip((BadgeVariant, String, IconData?) badge) =>
    StatusBadge(label: badge.$2, variant: badge.$1, icon: badge.$3);

// ── Tiers ─────────────────────────────────────────────────────────────────────

/// Banknote denomination tiers — bigger coin → bigger note.
///
/// The two ends are fixed amounts of the chain's own coin: at or under
/// [kDustSats] is dust whatever the wallet holds, and [kWhaleSats] or more is
/// a whale whatever the wallet holds. Everything in between is sized by its
/// share of that asset's holdings, so the percentage the list draws and the
/// size of the note on the wall are the same fact.
enum BanknoteTier { dust, small, big, huge, whale }

/// A coin of this many satoshis or fewer is dust — the relay floor, below
/// which spending it costs more than it is worth.
const int kDustSats = 546;

/// A coin of this many satoshis or more is a whale: one whole coin.
const int kWhaleSats = 100000000;

/// Share of holdings at or above which a coin is Huge.
const double kHugeShare = 0.25;

/// Share of holdings at or above which a coin is Big.
const double kBigShare = 0.05;

/// The tier of [u] given its [share] of the asset's holdings.
BanknoteTier utxoTier(Utxo u, double share) {
  if (u.isBtcLike) {
    if (u.amount <= kDustSats) return BanknoteTier.dust;
    if (u.amount >= kWhaleSats) return BanknoteTier.whale;
  }
  if (share >= kHugeShare) return BanknoteTier.huge;
  if (share >= kBigShare) return BanknoteTier.big;
  return BanknoteTier.small;
}

/// [utxoTier] with the share computed from [totals] (see [utxoAssetTotals]).
BanknoteTier utxoTierIn(Utxo u, Map<String, int> totals) =>
    utxoTier(u, utxoShareOf(u, totals));

// ── Shared share/tier math (single source for screen + picker) ────────────────

/// Groups UTXOs of the same asset (Liquid) or chain (BTC) together.
String utxoAssetKey(Utxo u) => u.assetId ?? u.ticker ?? 'BTC';

/// Per-asset totals — the denominator of every share-of-holdings ratio.
Map<String, int> utxoAssetTotals(List<Utxo> utxos) {
  final totals = <String, int>{};
  for (final u in utxos) {
    totals[utxoAssetKey(u)] = (totals[utxoAssetKey(u)] ?? 0) + u.amount;
  }
  return totals;
}

double utxoShareOf(Utxo u, Map<String, int> totals) {
  final total = totals[utxoAssetKey(u)] ?? 0;
  return total > 0 ? u.amount / total : 0.0;
}

/// `42%` from a tenth up, `4.2%` under it, `<0.1%` for crumbs — one decimal
/// of precision where it changes the reading and none where it would not.
String utxoShareText(double share) {
  final pct = share * 100;
  if (pct <= 0) return '0%';
  if (pct < 0.05) return '<0.1%';
  // Round to a tenth first, so 9.99 reads "10%" and not "10.0%".
  final tenths = (pct * 10).round() / 10;
  if (tenths >= 10) return '${tenths.round()}%';
  return '${tenths.toStringAsFixed(1)}%';
}

/// The height of every note on the wall. One height, so notes — and the
/// address trays that hold them — line up in rows; the width alone is the
/// denomination.
const double kNoteHeight = 112;

/// The corner of a note: paper is cut nearly square.
const double kNoteRadius = AppSpacing.radiusXs;

/// The face of a wall note: its writing and its seal never share paper.
///
/// The figures have a column of their own on the left — wide enough for an
/// eight-decimal amount and its unit, set whole — and the seal takes the
/// paper that column leaves free on the right. So a longer note carries a
/// larger seal, up to [sealMax], and past that the column grows instead.
abstract final class NoteFace {
  /// Where the writing starts, inside the note's edge.
  static const double inset = AppSpacing.md;

  /// The engraved frame's distance from the edge, and the seal's from the
  /// frame.
  static const double frame = AppSpacing.xs;

  /// Between the writing's column and the seal.
  static const double gap = AppSpacing.sm;

  /// The column of an amount in the chain's coin: `0.00019454 BTC`.
  static const double column = 148;

  /// The column of a dust note: counted in sats, three digits at the most.
  static const double dustColumn = 104;

  /// The largest seal: nearly the height of the paper inside its frame.
  static const double sealMax = 96;

  /// Edge, inset, gap, and the seal's two insets on the right: what a note
  /// [width] wide keeps from its column and its seal.
  static const double _fixed = 1 + inset + gap + 2 * frame;

  /// The seal of a note [width] wide whose writing needs [min].
  static double sealOf(double width, {double min = column}) =>
      (width - _fixed - min).clamp(0.0, sealMax);

  /// The writing's column on that note: [min], or what a full seal leaves.
  static double columnOf(double width, {double min = column}) =>
      math.max(min, width - _fixed - sealMax);
}

extension TierSpec on BanknoteTier {
  /// The note on the wall: [kNoteHeight] tall, longer the more it is worth.
  /// Each is long enough for its figures and a seal beside them
  /// ([NoteFace]).
  Size get size => switch (this) {
    BanknoteTier.dust => const Size(168, kNoteHeight),
    BanknoteTier.small => const Size(216, kNoteHeight),
    BanknoteTier.big => const Size(240, kNoteHeight),
    BanknoteTier.huge => const Size(304, kNoteHeight),
    BanknoteTier.whale => const Size(376, kNoteHeight),
  };

  /// The least column this tier's figures are set in ([NoteFace]).
  double get column =>
      this == BanknoteTier.dust ? NoteFace.dustColumn : NoteFace.column;

  /// The same note in miniature, for a list row ([MiniNote]): the five
  /// lengths again, so a column of them reads like the wall.
  double get miniWidth => switch (this) {
    BanknoteTier.dust => 28,
    BanknoteTier.small => 36,
    BanknoteTier.big => 44,
    BanknoteTier.huge => 54,
    BanknoteTier.whale => 64,
  };

  /// The tier's data hue (design.md, "Colour as data"): dust slate, small
  /// teal, big blue, huge violet, whale gold.
  Color hueIn(AppScheme s) => switch (this) {
    BanknoteTier.dust => s.hueSlate,
    BanknoteTier.small => s.hueTeal,
    BanknoteTier.big => s.hueBlue,
    BanknoteTier.huge => s.hueViolet,
    BanknoteTier.whale => s.hueGold,
  };

  /// The tier as a word, sentence case.
  String get label => switch (this) {
    BanknoteTier.dust => 'Dust',
    BanknoteTier.small => 'Small',
    BanknoteTier.big => 'Big',
    BanknoteTier.huge => 'Huge',
    BanknoteTier.whale => 'Whale',
  };

  /// The rule that put a coin in this tier, for the details sheet.
  String get rule => switch (this) {
    BanknoteTier.dust =>
      'At or under $kDustSats sats — costs more to '
          'spend than it is worth',
    BanknoteTier.small =>
      'Under ${(kBigShare * 100).round()}% of what '
          'you hold in this asset',
    BanknoteTier.big =>
      '${(kBigShare * 100).round()}–'
          '${(kHugeShare * 100).round()}% of what you hold in this asset',
    BanknoteTier.huge =>
      'Over ${(kHugeShare * 100).round()}% of what '
          'you hold in this asset',
    BanknoteTier.whale => 'A whole coin or more',
  };
}

// ── Small shared pieces ───────────────────────────────────────────────────────

/// `0.009 BTC` → (`0.009`, `BTC`). The engine hands the amount over as one
/// string; the figure and its unit are drawn in two voices.
(String, String?) _splitAmount(String display) {
  final i = display.lastIndexOf(' ');
  if (i <= 0 || i == display.length - 1) return (display, null);
  return (display.substring(0, i), display.substring(i + 1));
}

/// A coin's amount: the figure in [style] and the primary ink, the unit
/// beside it in [unitStyle] and the faint ink. Masked with the privacy eye.
class _CoinAmount extends StatelessWidget {
  const _CoinAmount(
    this.display, {
    required this.style,
    required this.unitStyle,
    this.ink,
    this.textAlign,
    this.scaleDown = false,
  });

  final String display;
  final TextStyle style;
  final TextStyle unitStyle;
  final Color? ink;
  final TextAlign? textAlign;

  /// Shrink the whole amount to the room it has instead of cutting it with
  /// an ellipsis: on a note the figure is the money, and half a figure is a
  /// different amount.
  final bool scaleDown;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final (figure, unit) = _splitAmount(display);
    final hidden = balancesHidden(context);
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: hidden ? kMaskedAmount : figure,
            style: style.copyWith(color: ink ?? s.ink),
          ),
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: unitStyle.copyWith(color: s.inkFaint),
            ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: scaleDown ? TextOverflow.visible : TextOverflow.ellipsis,
      textAlign: textAlign,
    );
    if (!scaleDown) return text;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: text,
    );
  }
}

/// The "i" on every coin: a way to the details sheet that does not toggle
/// the selection. A 48 dp square on a phone, a 28 px one on desktop.
class UtxoInfoButton extends StatelessWidget {
  const UtxoInfoButton({super.key, required this.onPressed, this.color});

  final VoidCallback onPressed;

  /// Overrides the secondary ink of the glyph.
  final Color? color;

  @override
  Widget build(BuildContext context) => _CoinIconButton(
    icon: Icons.info_outline,
    semanticLabel: 'Coin details',
    tooltip: 'Details',
    onPressed: onPressed,
    color: color,
  );
}

/// The label action on every coin of the coin screen: a tag glyph that
/// opens the label prompt. "Add label" on a bare coin, "Edit label" on one
/// the user has named. Same square as [UtxoInfoButton].
class UtxoLabelButton extends StatelessWidget {
  const UtxoLabelButton({
    super.key,
    required this.onPressed,
    required this.hasLabel,
  });

  final VoidCallback onPressed;

  /// The coin already carries a label: the action edits it.
  final bool hasLabel;

  @override
  Widget build(BuildContext context) => _CoinIconButton(
    icon: Icons.sell_outlined,
    semanticLabel: hasLabel ? 'Edit label' : 'Add label',
    tooltip: hasLabel ? 'Edit label' : 'Add label',
    onPressed: onPressed,
  );
}

/// A quiet icon square on a coin: 48 dp on a phone, 28 px on desktop.
class _CoinIconButton extends StatelessWidget {
  const _CoinIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String semanticLabel;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final side = phone
        ? AppLayout.minTouchTarget
        : AppSpacing.controlHeightSmall;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            hoverColor: s.hover,
            highlightColor: s.pressed,
            splashFactory: NoSplash.splashFactory,
            focusColor: s.hover,
            child: SizedBox(
              width: side,
              height: side,
              child: Icon(
                icon,
                size: phone ? 20 : AppSpacing.iconSmall,
                color: color ?? s.inkSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The share-of-holdings bar: a hairline track with the share drawn over
/// it — in the coin's tier hue on the coin screen, the secondary ink where
/// no tier is shown. Never shorter than a sliver, so a crumb still reads as
/// "a little", not "nothing".
class ShareMeter extends StatelessWidget {
  const ShareMeter({
    super.key,
    required this.share,
    this.color,
    this.height = 2,
  });

  final double share;

  /// The fill: the tier hue ([TierSpec.hueIn]), or the secondary ink when
  /// left null.
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: s.edge),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: share.clamp(0.02, 1.0),
              child: ColoredBox(color: color ?? s.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// `Huge · 12%` — the tier and the share it comes from, as one line. One
/// tag rather than two: the size of the note and the percentage are the
/// same fact, and reading them apart invited the question "why is this big?".
/// The tier word wears its hue; the share stays the faint ink.
class TierTag extends StatelessWidget {
  const TierTag({
    super.key,
    required this.tier,
    required this.share,
    this.color,
  });

  final BanknoteTier tier;
  final double share;

  /// The ink of the tier word: the tier hue on a printed note, a neutral
  /// ink on a drained one. Null leaves it to the faint ink.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final style = AppTypography.eyebrow.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: tier.label,
            style: style.copyWith(color: color ?? s.inkFaint),
          ),
          TextSpan(
            text: ' · ${utxoShareText(share)}',
            style: style.copyWith(color: s.inkFaint),
          ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The ticker [AssetLogo] draws for a coin: its own when the engine named
/// one, a token's drop for an unnamed Liquid asset, Bitcoin otherwise.
String utxoLogoTicker(Utxo u) =>
    u.ticker ?? (u.assetId != null ? 'TOKEN' : 'BTC');

/// A coin's state as a status (design.md, "Tag"): a 6 px dot and a word.
/// Dust is the warning dot — it costs more to spend than it is worth;
/// frozen and pending are neutral states, told by the word.
class UtxoStateMark extends StatelessWidget {
  const UtxoStateMark({super.key, required this.state});

  final UtxoState state;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final (word, dot) = switch (state) {
      UtxoState.available => (null, null),
      UtxoState.frozen => ('Frozen', s.inkSecondary),
      UtxoState.dusty => ('Dust', s.warning),
      UtxoState.unconfirmed => ('Pending', s.inkFaint),
    };
    if (word == null || dot == null) return const SizedBox.shrink();
    return _DotWord(word: word, dot: dot);
  }
}

class _DotWord extends StatelessWidget {
  const _DotWord({required this.word, required this.dot});

  final String word;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            word,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(color: s.inkSecondary),
          ),
        ),
      ],
    );
  }
}

/// A coin's glyph in a list: the asset's [AssetLogo] on a tile washed in
/// the coin's tier hue, with the hue's hairline — the list's half of the
/// note's colour. A frozen or pending coin's tile is drained to the raised
/// iron step, like its note.
///
/// With [asCheck] the tile is the phone row's checkbox as well: picked, it
/// turns to the accent with a check — a tick is the user's own mark — and a
/// small badge on its corner says frozen (the lock) or pending (a spinner).
class CoinGlyphTile extends StatelessWidget {
  const CoinGlyphTile({
    super.key,
    required this.utxo,
    required this.tier,
    this.size = AppSpacing.xxl + AppSpacing.sm,
    this.asCheck = false,
    this.drained,
  });

  final Utxo utxo;
  final BanknoteTier tier;
  final double size;
  final bool asCheck;

  /// Overrides "frozen or pending" as the reason to drain the tile.
  final bool? drained;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final u = utxo;
    final hue = tier.hueIn(s);
    final grey = drained ?? (u.isFrozen || u.isPending);
    final picked = asCheck && u.isSelected;
    final radius = BorderRadius.circular(AppSpacing.radiusMd);

    final tile = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.settle,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: picked ? s.accent : (grey ? s.panelInset : s.wash(hue)),
        borderRadius: radius,
        border: Border.all(
          color: picked ? s.accent : (grey ? s.edge : s.washEdge(hue)),
        ),
      ),
      child: picked
          ? Icon(
              u.isFrozen ? kFrozenIcon : Icons.check,
              size: AppSpacing.icon + 2,
              color: s.onAccent,
            )
          : Opacity(
              opacity: grey ? 0.6 : 1,
              child: AssetLogo(
                ticker: utxoLogoTicker(u),
                size: size - AppSpacing.lg,
              ),
            ),
    );
    if (!asCheck || picked || !(u.isFrozen || u.isPending)) return tile;

    const badge = AppSpacing.lg + 2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        Positioned(
          right: -AppSpacing.xs,
          bottom: -AppSpacing.xs,
          child: Container(
            width: badge,
            height: badge,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.panel,
              shape: BoxShape.circle,
              border: Border.all(color: s.edgeStrong),
            ),
            child: u.isPending
                ? const _LiveSpinner(size: AppSpacing.sm + 2)
                : Icon(kFrozenIcon, size: AppSpacing.md, color: s.inkSecondary),
          ),
        ),
      ],
    );
  }
}

/// The 16 px check of a row's checkbox, a frozen coin's lock. Mirrors the
/// app's themed checkbox: ticked, it is the accent — the user's own mark.
class _CoinCheck extends StatelessWidget {
  const _CoinCheck({
    required this.selected,
    this.size = AppSpacing.iconSmall,
    this.frozen = false,
  });

  final bool selected;
  final double size;

  /// Draw the lock in place of the box: a frozen coin is not picked for
  /// spending. Selected (to unfreeze it) the lock sits on the accent fill.
  final bool frozen;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final glyph = size - 4;
    if (frozen && !selected) {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(kFrozenIcon, size: glyph + 2, color: s.inkSecondary),
      );
    }
    return AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.settle,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? s.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        border: Border.all(
          color: selected ? s.accent : s.edgeStrong,
          width: 1.5,
        ),
      ),
      child: selected
          ? Icon(
              frozen ? kFrozenIcon : Icons.check,
              size: glyph,
              color: s.onAccent,
            )
          : null,
    );
  }
}

/// The small live spinner of a coin that has not landed yet.
class _LiveSpinner extends StatelessWidget {
  const _LiveSpinner({this.size = AppSpacing.iconSmall});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      valueColor: AlwaysStoppedAnimation(AppScheme.of(context).inkSecondary),
    ),
  );
}

// ── Provisional notes ─────────────────────────────────────────────────────────

/// The note that stands in for money that is not settled yet: a
/// consolidation waiting for its block, or a coin the mempool has and the
/// chain has not.
///
/// It is a real note drained to iron — grey paper, its engraving in faint
/// ink — with the loading it is going through drawn on it: a stroke runs
/// round its edge ([LiveEdge]) and a spinner sits beside the word that says
/// what it waits for. Grey because no block has counted it yet; moving
/// because something is still happening to it.
class ProvisionalNote extends StatelessWidget {
  const ProvisionalNote({
    super.key,
    required this.title,
    required this.displayAmount,
    required this.caption,
    required this.serial,
    this.seed = 0,
    this.size = const Size(304, kNoteHeight),
    this.radius = kNoteRadius,
    this.onInfo,
  });

  /// What is happening: "Consolidating", "Pending".
  final String title;
  final String displayAmount;

  /// One line under the amount saying what it waits for.
  final String caption;

  /// The txid or outpoint, shortened. Printed at the end of the first line
  /// where there is room for it beside the title; otherwise it is left to
  /// the details sheet.
  final String serial;

  /// What the engraving is drawn from: the outpoint or the txid, hashed.
  final int seed;

  /// Width, and the height the note is at least.
  final Size size;
  final double radius;

  /// Opens the details sheet, when there is one to open.
  final VoidCallback? onInfo;

  /// The least column that holds the title and the serial on one line.
  static const double _serialColumn = 200;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    // On the wall the note has a length: its writing keeps to its column
    // and its three lines stand where a banknote's do ([NoteFace]), so a
    // shelf of notes reads along one line. Full width (a phone), the lines
    // simply stack.
    final onWall = size.width.isFinite;
    final column = onWall ? NoteFace.columnOf(size.width) : double.infinity;
    final info = onInfo;
    final first = SizedBox(
      height: AppSpacing.controlHeightSmall,
      child: Row(
        children: [
          const _LiveSpinner(size: AppSpacing.md),
          const SizedBox(width: AppSpacing.sm),
          Text(
            title,
            style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
            maxLines: 1,
            softWrap: false,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            // The serial ends the first line where the column is long
            // enough to print it beside the title.
            child: column >= _serialColumn
                ? Text(
                    serial,
                    style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  )
                : const SizedBox.shrink(),
          ),
          if (info != null) ...[
            const SizedBox(width: AppSpacing.xs),
            UtxoInfoButton(onPressed: info),
          ],
        ],
      ),
    );
    final amount = _CoinAmount(
      displayAmount,
      style: AppTypography.balanceMedium,
      unitStyle: AppTypography.body,
      ink: s.inkSecondary,
      scaleDown: true,
    );
    final last = Text(
      caption,
      style: AppTypography.caption.copyWith(color: s.inkSecondary),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final Widget body = onWall
        ? Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: column,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  first,
                  const Spacer(),
                  amount,
                  const Spacer(),
                  SizedBox(
                    height: AppSpacing.controlHeightSmall,
                    child: Align(alignment: Alignment.centerLeft, child: last),
                  ),
                ],
              ),
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              first,
              const SizedBox(height: AppSpacing.xs),
              amount,
              const SizedBox(height: AppSpacing.xs),
              last,
            ],
          );
    final corner = BorderRadius.circular(radius);
    final frameRadius = BorderRadius.circular(
      (radius - AppSpacing.xs).clamp(2, radius),
    );
    // The drained seal, where the note's own will be once it lands. A
    // full-width note (a phone) has no fixed length to size one from.
    final crossInk = s.ink.withValues(alpha: s.isDark ? 0.18 : 0.14);
    final cross = onWall
        ? _CrossGuilloche.seal(
            seed: seed,
            color: crossInk,
            diameter: NoteFace.sealOf(size.width),
          )
        : _CrossGuilloche(seed: seed, color: crossInk);
    return LiveEdge(
      mode: LiveEdgeMode.working,
      color: s.inkSecondary,
      borderRadius: corner,
      child: Container(
        width: size.width,
        height: onWall ? size.height : null,
        constraints: onWall ? null : BoxConstraints(minHeight: size.height),
        decoration: BoxDecoration(
          color: s.panelInset,
          borderRadius: corner,
          border: Border.all(color: s.edge),
        ),
        child: Stack(
          children: [
            // The drained engraving: the inner frame and the cross, in the
            // faint ink a frozen note prints them in.
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs - 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: frameRadius,
                      border: Border.all(color: s.edge),
                    ),
                    child: ClipRRect(
                      borderRadius: frameRadius,
                      child: CustomPaint(painter: cross),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: body,
            ),
          ],
        ),
      ),
    );
  }
}

/// The placeholder that stands in for coins being merged.
///
/// The moment a consolidation is broadcast the coins it spends are gone as far
/// as the user's intent is concerned, so the wall shows one provisional note
/// where they were rather than N notes that are already spent.
class ConsolidatingNote extends StatelessWidget {
  const ConsolidatingNote({
    super.key,
    required this.count,
    required this.displayAmount,
    required this.txid,
    this.size = const Size(304, kNoteHeight),
  });

  /// How many coins are being merged into this one.
  final int count;

  /// Sum of the inputs — shown as an approximation, since the fee comes out of
  /// it and the exact figure only exists once the transaction confirms.
  final String displayAmount;

  final String txid;
  final Size size;

  @override
  Widget build(BuildContext context) => ProvisionalNote(
    title: 'Consolidating',
    displayAmount: displayAmount,
    caption: '$count coins → 1 · waiting for confirmation',
    serial: txid.length > 12 ? '${txid.substring(0, 12)}…' : txid,
    seed: _stableHash(txid),
    size: size,
  );
}

/// A coin the chain has not confirmed — a payment on its way in, or the
/// change of one on its way out: the same provisional note a consolidation
/// in flight gets, because it is the same situation — money no block has
/// counted yet. It is already the length of the note it will become.
class PendingCoinNote extends StatelessWidget {
  const PendingCoinNote({
    super.key,
    required this.utxo,
    required this.share,
    this.compact = false,
  });

  final Utxo utxo;
  final double share;

  /// Full-width phone note.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tier = utxoTier(utxo, share);
    return ProvisionalNote(
      title: 'Pending',
      displayAmount: utxo.displayAmount,
      caption: 'Waiting for confirmation',
      serial: compact ? utxo.midOutpoint : utxo.shortOutpoint,
      seed: _stableHash(utxo.outpoint),
      size: compact
          ? const Size(double.infinity, 84)
          // Never shorter than its own caption.
          : Size(
              math.max(tier.size.width, BanknoteTier.small.size.width),
              kNoteHeight,
            ),
      radius: compact ? AppSpacing.radiusLg : kNoteRadius,
      onInfo: () =>
          showUtxoDetails(context, utxo: utxo, share: share, tier: tier),
    );
  }
}

// ── Banknote ──────────────────────────────────────────────────────────────────

/// One UTXO rendered as a banknote — its length follows its tier.
///
/// The paper is the card washed with the tier's hue, the edge is the hue's
/// hairline, and the engraving that makes it a note and not a generic card
/// — a fine frame inside the edge and, on the wall, the Templar cross in
/// guilloche, drawn from the coin's own outpoint ([_CrossGuilloche]) — is
/// printed in the hue. The tier word is in it; the amount stays ink. Frozen and pending
/// drain the note back to iron. Selected is the hue's full edge and a
/// check on the corner; hover is a surface step.
///
/// On the wall a note is [kNoteHeight] tall whatever it carries: its tier
/// and share on the first line, the amount, then the label the user wrote
/// (or the outpoint, when there is none) — all in the writing's column,
/// with the seal on the paper to its right ([NoteFace]). Its two controls —
/// details and label — come over the end of the first and the last line
/// with the pointer, the keyboard focus or the selection, so a wall at
/// rest is only paper.
class UtxoBanknote extends StatefulWidget {
  const UtxoBanknote({
    super.key,
    required this.utxo,
    required this.tier,
    required this.onTap,
    this.share = 0,
    this.compact = false,
    this.onToggleFrozen,
    this.onEditLabel,
  });
  final Utxo utxo;
  final BanknoteTier tier;
  final VoidCallback onTap;

  /// Freezes or unfreezes this coin from its details sheet. Only the coin
  /// screen passes it; a picker shows the sheet without the button.
  final VoidCallback? onToggleFrozen;

  /// Opens the label prompt for this coin. With it the note carries a tag
  /// button in its foot and its label text is itself the way to edit it;
  /// without it (the send picker) the label is only printed.
  final VoidCallback? onEditLabel;

  /// Share of the asset's holdings — printed next to the tier.
  final double share;

  /// Full-width rendering for a phone column, where notes of five lengths
  /// would only leave a ragged single column. The tier is then carried by
  /// its word, its meter and the amount alone.
  final bool compact;

  @override
  State<UtxoBanknote> createState() => _UtxoBanknoteState();
}

class _UtxoBanknoteState extends State<UtxoBanknote> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  /// The keyboard focus is on the note or on one of its two controls.
  bool _focusWithin = false;

  Utxo get u => widget.utxo;

  void _details() => showUtxoDetails(
    context,
    utxo: u,
    share: widget.share,
    tier: widget.tier,
    onToggleFrozen: widget.onToggleFrozen,
  );

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final compact = widget.compact;
    final selected = u.isSelected;
    final frozen = u.isFrozen;
    final lit = _hover || _down;
    final size = widget.tier.size;
    final hue = widget.tier.hueIn(s);
    // Frozen and pending are states, not colours: the note goes back to
    // iron (a pending coin only reaches a banknote where it can be picked).
    final drained = frozen || u.isPending;
    // A dust note already says "Dust" in its tier word.
    final showState =
        u.state != UtxoState.available &&
        !(u.state == UtxoState.dusty && widget.tier == BanknoteTier.dust);
    final editLabel = widget.onEditLabel;
    // The wall's controls come with the pointer, the focus or the pick; a
    // phone has no pointer, so its full-width note always shows them.
    final controls = compact || _hover || _focusWithin || selected;

    // What a frozen note dims: the money and its facts, not the tag that
    // says why it is dim.
    Widget dim(Widget child) =>
        frozen ? Opacity(opacity: 0.55, child: child) : child;

    // The paper: the hue's wash. A drained note is plain iron.
    final paperFill = drained ? s.panel : s.wash(hue);
    final paperNow = lit ? Color.alphaBlend(s.hover, paperFill) : paperFill;

    // On the wall a control comes over the end of its line, on a patch of
    // the paper's own tone: it covers what is written there instead of
    // sitting on it, and the line never moves to make room.
    Widget control(Widget child) => compact
        ? child
        : IgnorePointer(
            ignoring: !controls,
            child: AnimatedOpacity(
              opacity: controls ? 1 : 0,
              duration: AppMotion.of(context, AppMotion.instant),
              curve: AppMotion.settle,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: paperNow,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: child,
              ),
            ),
          );

    final tierLine = Row(
      children: [
        Flexible(
          child: dim(
            TierTag(
              tier: widget.tier,
              share: widget.share,
              color: drained ? s.inkSecondary : hue,
            ),
          ),
        ),
        if (showState && !compact) ...[
          const SizedBox(width: AppSpacing.sm),
          UtxoStateMark(state: u.state),
        ],
      ],
    );
    final infoButton = control(UtxoInfoButton(onPressed: _details));

    final amount = dim(
      _CoinAmount(
        u.displayAmount,
        style: compact
            ? AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w500,
                fontFeatures: const [FontFeature.tabularFigures()],
              )
            : AppTypography.balanceMedium,
        unitStyle: compact ? AppTypography.caption : AppTypography.body,
        // A long token amount shrinks to the note; it is never cut.
        scaleDown: !compact,
      ),
    );

    // The user's label, printed on the note. Where it can be edited the
    // text is itself the way in, so a named coin is renamed by its name.
    Widget? labelText;
    if (u.label case final label?) {
      final text = Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption.copyWith(
          color: s.ink,
          fontWeight: FontWeight.w500,
        ),
      );
      labelText = dim(
        editLabel == null
            ? text
            : MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: editLabel,
                  child: text,
                ),
              ),
      );
    }
    final serial = dim(
      Text(
        compact ? u.midOutpoint : u.shortOutpoint,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
      ),
    );
    final labelButton = editLabel == null
        ? null
        : control(
            UtxoLabelButton(onPressed: editLabel, hasLabel: u.label != null),
          );

    final Widget content;
    if (compact) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _CoinCheck(selected: selected, frozen: frozen),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: tierLine),
              const SizedBox(width: AppSpacing.xs),
              infoButton,
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          amount,
          const SizedBox(height: AppSpacing.sm),
          dim(
            ShareMeter(
              share: widget.share,
              color: drained ? s.inkSecondary : hue,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showState) ...[
                      UtxoStateMark(state: u.state),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    ?labelText,
                    serial,
                  ],
                ),
              ),
              if (labelButton != null) ...[
                const SizedBox(width: AppSpacing.xs),
                labelButton,
              ],
            ],
          ),
        ],
      );
    } else {
      // The wall: three lines in a fixed height, set in the writing's
      // column — the seal has the paper to its right ([NoteFace]). The
      // label leads the last line and the outpoint follows it where the
      // column is wide enough; a dust note keeps the label and leaves the
      // outpoint to the details sheet.
      final column = NoteFace.columnOf(size.width, min: widget.tier.column);
      final long = column >= NoteFace.column;
      // A line of the note, with the control that comes over its end.
      Widget line(Widget text, Widget? button) => SizedBox(
        height: AppSpacing.controlHeightSmall,
        child: Stack(
          children: [
            Positioned.fill(child: text),
            if (button != null)
              Positioned(right: 0, top: 0, bottom: 0, child: button),
          ],
        ),
      );
      content = Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: column,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(tierLine, infoButton),
              const Spacer(),
              amount,
              const Spacer(),
              line(
                Row(
                  children: [
                    // The label keeps its own width; the outpoint takes
                    // what is left and is the one that gives way.
                    if (labelText != null && long) ...[
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: column * 0.6),
                        child: labelText,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: labelText != null && !long ? labelText : serial,
                    ),
                  ],
                ),
                labelButton,
              ),
            ],
          ),
        ),
      );
    }

    final radius = BorderRadius.circular(
      !compact
          ? kNoteRadius
          : AppLayout.isPhone(context)
          ? AppSpacing.radiusPhoneControl
          : AppSpacing.radiusLg,
    );
    // The engraved frame sits a few pixels inside the edge; its own corner
    // follows the nesting rule.
    final frameInset = compact ? 6.0 : AppSpacing.xs;
    final frameRadius = BorderRadius.circular(
      compact ? AppSpacing.radiusMd : 2,
    );
    // The paper's edge: the hue's hairline, the hue itself when picked or
    // under the pointer; iron on a drained note.
    final paperEdge = drained
        ? (selected || lit ? s.edgeStrong : s.edge)
        : (selected
              ? hue
              : (lit ? hue.withValues(alpha: 0.7) : s.washEdge(hue)));
    // The engraving: the inner frame and the cross, in the hue.
    final frameInk = drained
        ? s.edge
        : hue.withValues(alpha: s.isDark ? 0.26 : 0.3);
    // Printed clearly: the seal stands on paper of its own, so its ink can
    // be the hue at better than half strength.
    final crossInk = drained
        ? s.ink.withValues(alpha: s.isDark ? 0.18 : 0.14)
        : hue.withValues(alpha: s.isDark ? 0.62 : 0.55);
    // The engraving: a hairline frame inside the edge on every note, and on
    // the wall the cross as a seal beside the figures, as large as the
    // paper they leave free.
    final engraving = Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          // The paper's own 1 px edge is already inside this box.
          padding: EdgeInsets.all(frameInset - 1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: frameRadius,
              border: Border.all(color: frameInk),
            ),
            child: compact
                ? null
                : ClipRRect(
                    borderRadius: frameRadius,
                    child: CustomPaint(
                      painter: _CrossGuilloche.seal(
                        seed: _stableHash(u.outpoint),
                        color: crossInk,
                        diameter: NoteFace.sealOf(
                          size.width,
                          min: widget.tier.column,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
    final paper = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      width: compact ? double.infinity : size.width,
      height: compact ? null : size.height,
      decoration: BoxDecoration(
        color: paperNow,
        borderRadius: radius,
        border: Border.all(color: paperEdge),
        boxShadow: s.panelShadow,
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: Stack(
        children: [
          engraving,
          Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.lg,
                  )
                : const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
            child: content,
          ),
        ],
      ),
    );

    final engraved = Stack(
      clipBehavior: Clip.none,
      children: [
        paper,
        // The check sits on the note's corner, over the paper's edge, so
        // nothing on the note moves when a coin is picked. It is the
        // user's own mark, so it is the accent (design.md, "The accent").
        if (!compact)
          Positioned(
            top: -6,
            left: -6,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: AppMotion.of(context, AppMotion.quick),
                curve: AppMotion.settle,
                child: Container(
                  width: AppSpacing.cardPadding,
                  height: AppSpacing.cardPadding,
                  decoration: BoxDecoration(
                    color: s.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: s.panel, width: 2),
                  ),
                  child: Icon(Icons.check, size: 12, color: s.onAccent),
                ),
              ),
            ),
          ),
      ],
    );

    return Semantics(
      button: true,
      selected: selected,
      label: [
        '${widget.tier.label} coin ${maskAmount(context, u.displayAmount)}',
        ?u.label,
        if (frozen) 'frozen',
      ].join(', '),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (v) => setState(() => _focusWithin = v),
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
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            child: AnimatedScale(
              scale: AppMotion.reduced(context) || !_down ? 1.0 : 0.98,
              duration: AppMotion.of(context, AppMotion.instant),
              curve: AppMotion.settle,
              child: engraved,
            ),
          ),
        ),
      ),
    );
  }
}

/// FNV-1a over the code units: the same outpoint gives the same number on
/// every platform and every run, which `String.hashCode` does not promise.
int _stableHash(String text) {
  var h = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return h;
}

/// The outline of the cross pattée on the unit circle, sampled once: four
/// arms that are narrow at the centre and flare to the rim, each ending
/// where the next begins. The same geometry as the brand's mark
/// (`crossPattee` in seal_mark.dart), as one closed line.
final List<Offset> _unitCross = _buildUnitCross();

List<Offset> _buildUnitCross() {
  const waist = 0.14; // half-width where the arms meet
  const flare = 0.5; // half-width at the rim
  const steps = 20; // samples per curve
  Offset quad(Offset a, Offset c, Offset b, double t) {
    final u = 1 - t;
    return a * (u * u) + c * (2 * u * t) + b * (t * t);
  }

  // One arm pointing up: its left side, its faintly convex end, its right
  // side — from one waist corner round to the other.
  const p0 = Offset(-waist, -waist);
  const c0 = Offset(-waist * 1.1, -0.6);
  const p1 = Offset(-flare, -0.94);
  const c1 = Offset(0, -1.04);
  const p2 = Offset(flare, -0.94);
  const c2 = Offset(waist * 1.1, -0.6);
  const p3 = Offset(waist, -waist);
  final arm = <Offset>[
    for (var i = 0; i < steps; i++) quad(p0, c0, p1, i / steps),
    for (var i = 0; i < steps; i++) quad(p1, c1, p2, i / steps),
    for (var i = 0; i < steps; i++) quad(p2, c2, p3, i / steps),
  ];
  // Four arms a quarter turn apart.
  return [
    for (var quarter = 0; quarter < 4; quarter++)
      for (final p in arm)
        switch (quarter) {
          0 => p,
          1 => Offset(-p.dy, p.dx),
          2 => Offset(-p.dx, -p.dy),
          _ => Offset(p.dy, -p.dx),
        },
  ];
}

/// The engraving on a banknote: the Templar cross in guilloche — the
/// interlaced line-work printed on paper money so that no two plates are
/// alike — set in a braided ring, like the seal on a note.
///
/// The cross is a soft silhouette under a nest of its own outline: ring
/// inside ring down to the centre, each carrying a fine wave that shifts
/// from one ring to the next, so the lines weave. Its outermost line is the
/// firmest, so the shape reads at a glance. Round it runs a braid of three
/// scalloped circles. Here the plate is the coin: how many waves run round
/// the cross, how far they swing, how the rings interlace and how many
/// scallops the braid has all come from the outpoint, so every coin's note
/// is its own and the same coin always draws the same one.
///
/// It is printed in the tier's hue as a seal at the note's right edge, on
/// the paper the figures leave free ([NoteFace]): as large as that paper
/// allows, so the mark is whole and plain and the amount is never fought
/// for.
class _CrossGuilloche extends CustomPainter {
  const _CrossGuilloche({
    required this.seed,
    required this.color,
    this.rings = 7,
    this.stroke = 0.9,
    this.medallion = true,
  }) : diameter = null;

  /// The seal of a note: [diameter] across, with as many nested outlines
  /// as that size can hold apart — seven at full size, fewer on a short
  /// note, where seven would fill in.
  const _CrossGuilloche.seal({
    required this.seed,
    required this.color,
    required double this.diameter,
  }) : rings = diameter >= 80
           ? 7
           : diameter >= 56
           ? 5
           : 3,
       stroke = diameter >= 56 ? 0.9 : 0.75,
       medallion = true;

  final int seed;

  /// The ink at its strongest: the cross's outer line and the braid.
  final Color color;

  /// How many nested outlines are drawn: seven on a note, fewer on its
  /// miniature, where seven would fill in.
  final int rings;
  final double stroke;

  /// Draw the braided ring round the cross: a seal. Off on a miniature:
  /// there the cross alone fills the paper.
  final bool medallion;

  /// The seal's width across its braid. Null fills the paper's height.
  final double? diameter;

  static const int _ringSteps = 180;

  @override
  void paint(Canvas canvas, Size size) {
    final waves = 8 + 4 * (seed % 4); // 8, 12, 16 or 20 round the cross
    final depth = 0.018 + ((seed >> 4) % 5) * 0.005; // how far a wave swings
    final twist = ((seed >> 8) % 3) + 1; // how the rings interlace
    final scallops = 12 + 2 * ((seed >> 12) % 5); // 12–20 round the braid

    final radius = medallion
        ? math.min(diameter ?? size.height * 0.92, size.height * 0.92) / 2
        : size.height * 0.44;
    if (radius <= 0) return;
    // Whole on the paper, against its right edge.
    final center = Offset(
      math.max(
        size.width / 2,
        size.width - radius - (medallion ? NoteFace.frame : radius * 0.22),
      ),
      size.height / 2,
    );

    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // The braid: three scalloped circles, each a third of a scallop on.
    if (medallion) {
      pen
        ..strokeWidth = stroke * 0.8
        ..color = color.withValues(alpha: color.a * 0.75);
      for (var k = 0; k < 3; k++) {
        final phase = 2 * math.pi * k / 3;
        final path = Path();
        for (var i = 0; i <= _ringSteps; i++) {
          final t = 2 * math.pi * i / _ringSteps;
          final r = radius * (0.955 + 0.045 * math.cos(scallops * t + phase));
          final point = center + Offset(r * math.cos(t), r * math.sin(t));
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(path..close(), pen);
      }
    }

    // The cross: its silhouette, soft, then the nest of its outline.
    final reach = radius * (medallion ? 0.8 : 1.0);
    final n = _unitCross.length;
    Path outline(double scale, double swing, double phase) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final k =
            reach *
            scale *
            (1 + swing * math.cos(2 * math.pi * waves * i / n + phase));
        final point = center + _unitCross[i] * k;
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      return path..close();
    }

    canvas.drawPath(
      outline(1, 0, 0),
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: color.a * 0.2),
    );
    for (var ring = 0; ring < rings; ring++) {
      final phase = 2 * math.pi * ring * twist / rings;
      final scale = 1 - ring * (0.8 / rings);
      // The outer line is firm and still; the waves begin inside it.
      pen
        ..strokeWidth = ring == 0 ? stroke * 1.5 : stroke
        ..color = color.withValues(
          alpha: color.a * (ring == 0 ? 1 : 0.85 - 0.35 * ring / rings),
        );
      canvas.drawPath(outline(scale, ring == 0 ? 0 : depth, phase), pen);
    }
  }

  @override
  bool shouldRepaint(_CrossGuilloche old) =>
      old.seed != seed ||
      old.color != color ||
      old.rings != rings ||
      old.stroke != stroke ||
      old.medallion != medallion ||
      old.diameter != diameter;
}

// ── List ──────────────────────────────────────────────────────────────────────

/// Fixed desktop column widths, shared by the rows and the header above
/// them so the two never drift apart.
abstract final class CoinColumns {
  static const double check = AppSpacing.iconSmall;

  /// The slot the coin's miniature note sits in: as long as a whale's.
  static const double note = 64;

  /// The address the coin sits on, under the label the user gave it.
  static const double address = 184;

  /// The tier word, the share and the meter that draws it.
  static const double share = 132;
  static const double amount = 152;

  /// One action square (label, details).
  static const double action = AppSpacing.controlHeightSmall;

  /// Every row is this tall: a miniature note and two lines of text.
  static const double rowHeight = AppSpacing.huge;

  /// Narrower than this (the send wizard's card) the tier column folds into
  /// the row's second line.
  static const double wideMin = 720;

  /// From this width up the row has room for the address column too.
  static const double addressMin = 880;

  /// Where the text starts, past the check and note columns — the
  /// dividers are indented to here so the card reads as one object with an
  /// icon column (design.md, "Rows, not a card each").
  static const double textInset =
      AppSpacing.lg + check + AppSpacing.md + note + AppSpacing.md;

  /// The trailing action squares: details alone, or label and details.
  static double actions({required bool label}) =>
      label ? 2 * action + AppSpacing.xs : action;
}

/// Phone: the glyph tile — which is also the checkbox — sits in a 48 dp
/// target 4 in, then 8 to the text: the same 60 the app's [ListCard]
/// indents its hairlines to.
const double _phoneLead = AppLayout.minTouchTarget;
const double _phoneTextInset = AppSpacing.xs + _phoneLead + AppSpacing.sm;

/// The phone row's glyph tile ([CoinGlyphTile]), which is its checkbox.
const double _phoneGlyph = AppSpacing.xxl + AppSpacing.sm;

/// Where a phone coin row's text starts: the inset of the hairline between
/// two rows, for a host that rules them itself (a section per address).
const double kPhoneCoinTextInset = _phoneTextInset;

/// `6 confirmations` — what a bare coin's second line says.
String _confirmationsText(Utxo u) => switch (u.confirmations) {
  <= 0 => 'Not in a block yet',
  1 => '1 confirmation',
  final n => '$n confirmations',
};

/// A coin's note in miniature, at the head of a desktop list row: the paper
/// washed in the tier's hue, its edge and its cross — the wall's note, a
/// quarter the size. Its length is the tier's ([TierSpec.miniWidth]), so a
/// column of rows shows how the coins compare before a figure is read. A
/// frozen coin's is drained to iron, and so is one that is not settled: the
/// grey note it is on the wall (the row's spinner says it is on its way).
class MiniNote extends StatelessWidget {
  const MiniNote({
    super.key,
    required this.tier,
    required this.seed,
    this.drained = false,
    this.provisional = false,
  });

  /// The coin's own note.
  MiniNote.of(Utxo utxo, {super.key, required this.tier})
    : seed = _stableHash(utxo.outpoint),
      drained = utxo.isFrozen,
      provisional = utxo.isPending;

  final BanknoteTier tier;

  /// What the cross is drawn from: the coin's outpoint, hashed.
  final int seed;
  final bool drained;
  final bool provisional;

  static const double height = AppSpacing.xl;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final hue = tier.hueIn(s);
    final width = tier.miniWidth;
    const radius = 3.0;
    final grey = drained || provisional;
    final note = Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: grey ? s.panelInset : s.wash(hue),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: grey ? s.edgeStrong : s.washEdge(hue)),
      ),
      child: CustomPaint(
        painter: _CrossGuilloche(
          seed: seed,
          color: grey
              ? s.ink.withValues(alpha: s.isDark ? 0.22 : 0.16)
              : hue.withValues(alpha: s.isDark ? 0.8 : 0.7),
          rings: 3,
          stroke: 0.6,
          medallion: false,
        ),
      ),
    );
    return SizedBox(
      width: CoinColumns.note,
      height: height,
      child: Align(alignment: Alignment.centerLeft, child: note),
    );
  }
}

/// The card a run of [CoinRow]s sits on: one panel, hairlines between rows,
/// indented past the icon column. Repeated things are one object
/// (design.md).
class CoinListCard extends StatelessWidget {
  const CoinListCard({super.key, required this.children, this.header});

  final List<Widget> children;

  /// A table head ([CoinTableHeader]) above the first row, on desktop.
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final head = header;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        children: [
          if (head != null) ...[
            head,
            Divider(height: 1, thickness: 1, color: s.edge),
          ],
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: s.edge,
                indent: phone ? _phoneTextInset : CoinColumns.textInset,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The desktop table head: `Coin`, `Address`, `Share`, `Amount` in
/// `eyebrow` and the faint ink, aligned on [CoinColumns]. A sortable head
/// shows a small arrow in the secondary ink when it is the active sort.
class CoinTableHeader extends StatelessWidget {
  const CoinTableHeader({
    super.key,
    required this.sortBy,
    required this.sortAsc,
    required this.onSort,
    this.showShare = true,
    this.labelAction = true,
  });

  /// `'amount'`, `'label'` or `'address'`.
  final String sortBy;
  final bool sortAsc;
  final ValueChanged<String> onSort;
  final bool showShare;

  /// The rows carry a label action beside their details: reserve its
  /// square so the columns line up.
  final bool labelAction;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    Widget cell(String label, String? by, {bool end = false}) {
      final active = by != null && by == sortBy;
      final text = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: AppTypography.eyebrow.copyWith(color: s.inkFaint)),
          if (active) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(
              sortAsc ? '↑' : '↓',
              style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
            ),
          ],
        ],
      );
      final Widget body = by == null
          ? text
          : Semantics(
              button: true,
              label: 'Sort by $label',
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSort(by),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: text,
                  ),
                ),
              ),
            );
      return Align(
        alignment: end ? Alignment.centerRight : Alignment.centerLeft,
        child: body,
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= CoinColumns.wideMin;
        final withAddress = c.maxWidth >= CoinColumns.addressMin;
        return SizedBox(
          height: AppSpacing.xxl + AppSpacing.sm,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                const SizedBox(
                  width:
                      CoinColumns.check +
                      AppSpacing.md +
                      CoinColumns.note +
                      AppSpacing.md,
                ),
                Expanded(child: cell('Coin', 'label')),
                if (withAddress) ...[
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(
                    width: CoinColumns.address,
                    child: cell('Address', 'address'),
                  ),
                ],
                if (wide) ...[
                  const SizedBox(width: AppSpacing.lg),
                  SizedBox(
                    width: CoinColumns.share,
                    child: cell(showShare ? 'Share' : 'Tier', null),
                  ),
                ],
                const SizedBox(width: AppSpacing.lg),
                SizedBox(
                  width: CoinColumns.amount,
                  child: cell('Amount', 'amount', end: true),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(width: CoinColumns.actions(label: labelAction)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One coin as a row of the [CoinListCard].
///
/// Desktop: a 64 tall row — check, the coin's note in miniature, the label
/// (or the outpoint) over its second line, the address it sits on under
/// that address's own label, the tier word with the share and its meter in
/// the hue, the amount over its fiat value, then the label and details
/// actions. Phone: the glyph tile is the checkbox (48 dp); the label and
/// the amount on the first line, the outpoint and the state on the second,
/// the tier and its meter under them.
///
/// A pending coin draws as a row of the same shape with a spinner where the
/// check would be: it is listed so the wallet shows what is on its way, and
/// it cannot be picked until a block includes it.
class CoinRow extends StatefulWidget {
  const CoinRow({
    super.key,
    required this.utxo,
    required this.share,
    required this.onTap,
    this.showShare = true,
    this.compact,
    this.allowPending = false,
    this.lockFrozen = false,
    this.onToggleFrozen,
    this.tapOpensDetails = false,
    this.onEditLabel,
    this.onEditAddressLabel,
  });

  final Utxo utxo;
  final double share;

  /// Toggles the coin's selection.
  final VoidCallback onTap;

  /// A frozen coin cannot be picked. On where picking means spending (the
  /// send wizard's coin picker); off on the coin screen, where a frozen coin
  /// is selected to be tagged or unfrozen.
  final bool lockFrozen;

  /// Freezes or unfreezes this coin from its details sheet (coin screen
  /// only).
  final VoidCallback? onToggleFrozen;

  /// Opens the label prompt for this coin (coin screen only): the row then
  /// carries a label action beside its details.
  final VoidCallback? onEditLabel;

  /// Opens the label prompt for the address this coin sits on (coin screen
  /// only): the address cell is then its own editor, as it is on Receive.
  final VoidCallback? onEditAddressLabel;

  /// Let a pending coin be selected. Off by default — the coin screen
  /// waits for a block — and on where the engine really can spend an
  /// unconfirmed output (the LiquiDEX offer flow, whose "create exact coin"
  /// lands unconfirmed and must be pickable at once). The row still wears
  /// its spinner and Pending state either way.
  final bool allowPending;

  /// Hide the share meter + percentage (Liquid rows: shares across mixed
  /// assets read as noise). The tier word stays.
  final bool showShare;

  /// Stacked phone row instead of the fixed-column row. `null` (the default)
  /// resolves from [AppLayout.isPhone], so every caller — including the
  /// send wizard's picker inside a 337 dp card — gets the right layout;
  /// desktop always gets the table row.
  final bool? compact;

  /// Phone, coin screen: the row opens the details sheet and only the
  /// glyph tile selects. Off, the whole row selects and the "i" opens the
  /// details — the picker's grammar, where picking is the point.
  final bool tapOpensDetails;

  @override
  State<CoinRow> createState() => _CoinRowState();
}

class _CoinRowState extends State<CoinRow> {
  bool _hover = false;
  bool _focus = false;

  Utxo get u => widget.utxo;
  bool get pending => u.isPending;

  /// No check, no tap: pending and not allowed, or frozen where picking
  /// would mean spending.
  bool get locked =>
      (pending && !widget.allowPending) || (widget.lockFrozen && u.isFrozen);
  BanknoteTier get tier => utxoTier(u, widget.share);

  void _details() => showUtxoDetails(
    context,
    utxo: u,
    share: widget.share,
    tier: tier,
    onToggleFrozen: widget.onToggleFrozen,
  );

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    if (widget.compact ?? AppLayout.isPhone(context)) {
      return _compactRow(context, s: s);
    }
    return _desktopRow(context, s: s);
  }

  /// The check column: a spinner while the coin is on its way, the lock for
  /// a frozen coin, the checkbox otherwise.
  Widget _lead(double size) {
    if (pending) return _LiveSpinner(size: size);
    if (locked) {
      return _CoinCheck(selected: false, frozen: true, size: size);
    }
    return _CoinCheck(selected: u.isSelected, frozen: u.isFrozen, size: size);
  }

  /// Frozen and pending drain the tier hue to the neutral ink, as they
  /// drain a note to iron.
  Color _tierInk(AppScheme s) =>
      u.isFrozen || pending ? s.inkSecondary : tier.hueIn(s);

  /// The address column's cell: the label the user gave the address over
  /// the address itself, or the address alone. With an editor it is a
  /// target of its own, so a click on it never toggles the row.
  Widget _addressCell(AppScheme s) {
    final short = u.shortAddress;
    if (short == null) {
      return Text('—', style: AppTypography.body.copyWith(color: s.inkFaint));
    }
    final name = AddressLabelStore.instance.labelFor(u.address!);
    final hue = addressHueOf(s, u.address!);
    final address = Text(
      short,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: (name == null ? AppTypography.mono : AppTypography.monoSmall)
          .copyWith(color: name == null ? s.inkSecondary : s.inkFaint),
    );
    // The address's own colour leads the cell: a tag when it has a label,
    // a square of the colour when it has none. Coins that share an address
    // share it, down the column.
    final cell = name != null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AddressTag(label: name, hue: hue),
              const SizedBox(height: 2),
              address,
            ],
          )
        : Row(
            children: [
              AddressSwatch(hue: hue),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: address),
            ],
          );
    final edit = widget.onEditAddressLabel;
    if (edit == null) return cell;
    return Tooltip(
      message: name == null ? 'Label this address' : 'Edit address label',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: edit,
          child: Align(alignment: Alignment.centerLeft, child: cell),
        ),
      ),
    );
  }

  Widget _desktopRow(BuildContext context, {required AppScheme s}) {
    final selected = u.isSelected;
    final tierInk = _tierInk(s);
    final editLabel = widget.onEditLabel;
    final label = u.label;
    // A dust coin's tier word already says "Dust".
    final showState =
        u.state != UtxoState.available &&
        !(u.state == UtxoState.dusty && tier == BanknoteTier.dust);
    final fiat = u.isBtcLike && !balancesHidden(context)
        ? PriceService.instance.fiatDisplay(u.amount)
        : null;
    Widget dim(Widget child) =>
        u.isFrozen ? Opacity(opacity: 0.55, child: child) : child;

    Widget row(double width) {
      final wide = width >= CoinColumns.wideMin;
      final withAddress = width >= CoinColumns.addressMin;
      final meta = AppTypography.caption.copyWith(color: s.inkFaint);
      final title = label != null
          ? Text(
              label,
              style: AppTypography.body.copyWith(color: s.ink),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : Text(
              u.shortOutpoint,
              style: AppTypography.mono.copyWith(
                color: pending ? s.inkSecondary : s.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
      final subtitle = Text.rich(
        TextSpan(
          children: [
            if (label != null) ...[
              TextSpan(
                text: u.shortOutpoint,
                style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
              ),
              TextSpan(text: ' · ', style: meta),
            ],
            if (pending)
              TextSpan(
                text: 'Waiting for confirmation',
                style: AppTypography.caption.copyWith(color: s.inkSecondary),
              )
            else
              TextSpan(text: _confirmationsText(u), style: meta),
            // No room for the tier column: the tier rides on this line.
            if (!wide) ...[
              TextSpan(text: ' · ', style: meta),
              TextSpan(
                text: tier.label,
                style: AppTypography.label.copyWith(color: tierInk),
              ),
              if (widget.showShare)
                TextSpan(
                  text: ' · ${utxoShareText(widget.share)}',
                  style: meta,
                ),
            ],
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );

      final tierCell = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                tier.label,
                style: AppTypography.label.copyWith(color: tierInk),
              ),
              const Spacer(),
              if (widget.showShare)
                Text(
                  utxoShareText(widget.share),
                  style: AppTypography.numericSmall.copyWith(
                    color: s.inkSecondary,
                  ),
                ),
            ],
          ),
          if (widget.showShare) ...[
            const SizedBox(height: AppSpacing.xs),
            ShareMeter(
              share: widget.share,
              color: tierInk,
              height: AppSpacing.xs,
            ),
          ],
        ],
      );

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            SizedBox(
              width: CoinColumns.check,
              child: Center(child: _lead(CoinColumns.check)),
            ),
            const SizedBox(width: AppSpacing.md),
            MiniNote.of(u, tier: tier),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(child: dim(title)),
                      if (showState) ...[
                        const SizedBox(width: AppSpacing.md),
                        UtxoStateMark(state: u.state),
                      ],
                    ],
                  ),
                  dim(subtitle),
                ],
              ),
            ),
            if (withAddress) ...[
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: CoinColumns.address, child: dim(_addressCell(s))),
            ],
            if (wide) ...[
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: CoinColumns.share, child: dim(tierCell)),
            ],
            const SizedBox(width: AppSpacing.lg),
            SizedBox(
              width: CoinColumns.amount,
              child: dim(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CoinAmount(
                      u.displayAmount,
                      style: AppTypography.numeric,
                      unitStyle: AppTypography.caption,
                      ink: pending ? s.inkSecondary : s.ink,
                      textAlign: TextAlign.right,
                    ),
                    if (fiat != null)
                      Text(
                        fiat,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.numericSmall.copyWith(
                          color: s.inkFaint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (editLabel != null) ...[
              UtxoLabelButton(onPressed: editLabel, hasLabel: label != null),
              const SizedBox(width: AppSpacing.xs),
            ],
            SizedBox(
              width: CoinColumns.action,
              child: UtxoInfoButton(onPressed: _details),
            ),
          ],
        ),
      );
    }

    final enabled = !locked;
    return Semantics(
      button: enabled,
      selected: selected,
      label: _semanticLabel(context),
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: enabled ? widget.onTap : null,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.quick),
            curve: AppMotion.settle,
            constraints: const BoxConstraints(minHeight: CoinColumns.rowHeight),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            color: selected
                ? s.selected
                : (_hover && enabled ? s.hover : Colors.transparent),
            foregroundDecoration: _focus && enabled
                ? BoxDecoration(
                    border: Border.all(color: s.focus, width: 2),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                  )
                : null,
            child: LayoutBuilder(builder: (context, c) => row(c.maxWidth)),
          ),
        ),
      ),
    );
  }

  String _semanticLabel(BuildContext context) {
    final amount = maskAmount(context, u.displayAmount);
    final named = u.label == null ? '' : ', ${u.label}';
    if (pending) {
      return 'Pending coin $amount$named, waiting for confirmation';
    }
    if (u.isFrozen) return 'Frozen ${tier.label} coin $amount$named';
    return '${tier.label} coin $amount$named';
  }

  /// Phone row, at least 64 tall. Leading: the glyph tile in its own 48 dp
  /// target, which is the checkbox too (a spinner badge while pending, the
  /// lock when frozen, the ink and a check once picked). Text column: the
  /// label or the outpoint and the amount; the outpoint or the coin's age
  /// and its state; the tier word and its meter in the hue. Trailing: the
  /// label action (coin screen) or the details button (picker).
  Widget _compactRow(BuildContext context, {required AppScheme s}) {
    final selected = u.isSelected;
    final opensDetails = widget.tapOpensDetails;
    final tierInk = _tierInk(s);
    final editLabel = widget.onEditLabel;
    final label = u.label;
    // A dust coin's tier word already says "Dust".
    final showState =
        u.state != UtxoState.available &&
        !(u.state == UtxoState.dusty && tier == BanknoteTier.dust);
    Widget dim(Widget child) =>
        u.isFrozen ? Opacity(opacity: 0.55, child: child) : child;

    // In the details grammar the tile is the only way to select, so it owns
    // a 48 dp target of its own; otherwise the whole row is the target.
    final lead = SizedBox(
      width: _phoneLead,
      height: _phoneLead,
      child: Center(
        child: CoinGlyphTile(
          utxo: u,
          tier: tier,
          size: _phoneGlyph,
          asCheck: true,
        ),
      ),
    );
    final leadTarget = opensDetails && !locked
        ? Semantics(
            checked: selected,
            label: 'Select',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: lead,
            ),
          )
        : lead;

    final title = label != null
        ? Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyOf(context).copyWith(color: s.ink),
          )
        : Text(
            u.midOutpoint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.mono.copyWith(
              color: pending ? s.inkSecondary : s.ink,
            ),
          );
    final subtitle = pending && label == null
        ? Text(
            'Waiting for confirmation',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          )
        : label != null
        ? Text(
            u.midOutpoint,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
          )
        : Text(
            _confirmationsText(u),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: s.inkFaint),
          );

    final text = LayoutBuilder(
      builder: (context, c) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: dim(title)),
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: c.maxWidth * 0.62),
                child: dim(
                  _CoinAmount(
                    u.displayAmount,
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    unitStyle: AppTypography.caption,
                    ink: pending ? s.inkSecondary : s.ink,
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(child: dim(subtitle)),
              if (showState) ...[
                const SizedBox(width: AppSpacing.sm),
                UtxoStateMark(state: u.state),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          dim(
            Row(
              children: [
                Text(
                  tier.label,
                  style: AppTypography.label.copyWith(color: tierInk),
                ),
                if (widget.showShare) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    utxoShareText(widget.share),
                    style: AppTypography.numericSmall.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: ShareMeter(
                      share: widget.share,
                      color: tierInk,
                      height: AppSpacing.xs,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final Widget trailing = editLabel != null
        ? UtxoLabelButton(onPressed: editLabel, hasLabel: label != null)
        : opensDetails
        ? SizedBox(
            width: _phoneLead,
            child: Icon(Icons.chevron_right, size: 20, color: s.inkFaint),
          )
        : UtxoInfoButton(onPressed: _details);

    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.settle,
      constraints: const BoxConstraints(minHeight: AppSpacing.huge),
      color: selected ? s.selected : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          leadTarget,
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: text),
          const SizedBox(width: AppSpacing.xs),
          trailing,
        ],
      ),
    );

    final VoidCallback? onRow = opensDetails
        ? _details
        : (locked ? null : widget.onTap);
    return Semantics(
      button: onRow != null,
      selected: selected,
      label: _semanticLabel(context),
      child: Material(
        type: MaterialType.transparency,
        child: onRow == null
            ? body
            : InkWell(
                onTap: onRow,
                highlightColor: s.pressed,
                splashFactory: NoSplash.splashFactory,
                child: body,
              ),
      ),
    );
  }
}

/// The drained glyph tile of something not settled: the chain's logo on
/// the raised iron step, a spinner on its corner.
class _SettlingTile extends StatelessWidget {
  const _SettlingTile();

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    const badge = AppSpacing.lg + 2;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: _phoneGlyph,
          height: _phoneGlyph,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: s.panelInset,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: s.edge),
          ),
          child: const Opacity(
            opacity: 0.6,
            child: AssetLogo(ticker: 'BTC', size: _phoneGlyph - AppSpacing.lg),
          ),
        ),
        Positioned(
          right: -AppSpacing.xs,
          bottom: -AppSpacing.xs,
          child: Container(
            width: badge,
            height: badge,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.panel,
              shape: BoxShape.circle,
              border: Border.all(color: s.edgeStrong),
            ),
            child: const _LiveSpinner(size: AppSpacing.sm + 2),
          ),
        ),
      ],
    );
  }
}

/// A consolidation in flight as a row of the [CoinListCard]: a drained
/// tile with a spinner, the summed inputs as the amount, the txid as the
/// coin. It leads the list, the same place its note takes on the wall.
class ConsolidatingCoinRow extends StatelessWidget {
  const ConsolidatingCoinRow({
    super.key,
    required this.count,
    required this.displayAmount,
    required this.txid,
    this.compact,
  });

  final int count;
  final String displayAmount;
  final String txid;

  /// See [CoinRow.compact].
  final bool? compact;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final short = txid.length > 12 ? '${txid.substring(0, 12)}…' : txid;
    final what = '$count coins → 1 · waiting for confirmation';
    final state = _DotWord(word: 'Consolidating', dot: s.inkFaint);
    final amount = _CoinAmount(
      displayAmount,
      style: compact ?? AppLayout.isPhone(context)
          ? AppTypography.bodyLarge.copyWith(
              fontWeight: FontWeight.w500,
              fontFeatures: const [FontFeature.tabularFigures()],
            )
          : AppTypography.numeric,
      unitStyle: AppTypography.caption,
      ink: s.inkSecondary,
      textAlign: TextAlign.right,
    );

    if (compact ?? AppLayout.isPhone(context)) {
      return Container(
        constraints: const BoxConstraints(minHeight: AppSpacing.huge),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            const SizedBox(
              width: _phoneLead,
              height: _phoneLead,
              child: Center(child: _SettlingTile()),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          short,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.mono.copyWith(
                            color: s.inkSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(child: amount),
                    ],
                  ),
                  Text(
                    what,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  state,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= CoinColumns.wideMin;
        final withAddress = c.maxWidth >= CoinColumns.addressMin;
        return Container(
          constraints: const BoxConstraints(minHeight: CoinColumns.rowHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const SizedBox(
                width: CoinColumns.check,
                child: Center(child: _LiveSpinner()),
              ),
              const SizedBox(width: AppSpacing.md),
              // The note it will be: one coin, whose size no block has
              // fixed yet.
              MiniNote(
                tier: BanknoteTier.huge,
                seed: _stableHash(txid),
                provisional: true,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            short,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.mono.copyWith(
                              color: s.inkSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        state,
                      ],
                    ),
                    Text(
                      what,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (withAddress)
                const SizedBox(width: AppSpacing.lg + CoinColumns.address),
              if (wide)
                const SizedBox(width: AppSpacing.lg + CoinColumns.share),
              const SizedBox(width: AppSpacing.lg),
              SizedBox(width: CoinColumns.amount, child: amount),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(width: CoinColumns.actions(label: true)),
            ],
          ),
        );
      },
    );
  }
}

/// Embeddable coin-control picker: notes/list toggle + selection stats.
/// The send wizard uses this for manual input selection; state (which coins
/// are selected) lives in the parent via [Utxo.isSelected] + [onToggle].
class UtxoPicker extends StatefulWidget {
  const UtxoPicker({
    super.key,
    required this.utxos,
    required this.onToggle,
    this.maxHeight = 420,
    this.allowPending = false,
  });

  /// The coins to pick from, selection carried by [Utxo.isSelected]. Frozen
  /// coins are shown so the total adds up, but cannot be picked.
  final List<Utxo> utxos;

  /// Called with the index (into [utxos]) of the tapped coin.
  final void Function(int index) onToggle;

  final double maxHeight;

  /// See [CoinRow.allowPending]. With it on, a pending coin is drawn as a
  /// banknote wearing a Pending tag rather than the provisional note.
  final bool allowPending;

  @override
  State<UtxoPicker> createState() => _UtxoPickerState();
}

class _UtxoPickerState extends State<UtxoPicker> {
  bool _notesView = false;

  /// Indices of [UtxoPicker.utxos] ordered biggest-first, so both views read
  /// as a value hierarchy (whale notes first). Selection callbacks still use
  /// the original indices.
  List<int> get _sortedIndices {
    final idx = List<int>.generate(widget.utxos.length, (i) => i);
    idx.sort(
      (a, b) => widget.utxos[b].amount.compareTo(widget.utxos[a].amount),
    );
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final utxos = widget.utxos;
    final totals = utxoAssetTotals(utxos);
    final order = _sortedIndices;
    final phone = AppLayout.isPhone(context);
    final frozenCount = utxos.where((u) => u.isFrozen).length;

    // Both callers embed the picker in a scrolling step, so on a phone the
    // list sizes to its content instead of nesting a second scroll region.
    final toggle = SegmentedSwitch<bool>(
      selected: _notesView,
      onChanged: (v) => setState(() => _notesView = v),
      options: const [
        SegOption(value: false, label: 'List', tooltip: 'Coins as rows'),
        SegOption(value: true, label: 'Notes', tooltip: 'Coins as banknotes'),
      ],
    );

    Widget note(int i) {
      final share = utxoShareOf(utxos[i], totals);
      if (utxos[i].isPending && !widget.allowPending) {
        return PendingCoinNote(utxo: utxos[i], share: share, compact: phone);
      }
      return UtxoBanknote(
        utxo: utxos[i],
        tier: utxoTier(utxos[i], share),
        share: share,
        onTap: utxos[i].isFrozen ? () {} : () => widget.onToggle(i),
        compact: phone,
      );
    }

    // Coins are picked under the address they sit on, as they are kept on
    // the coin screen: spending two coins of one address together links
    // nothing new, spending coins of two addresses links those addresses —
    // the address's card is what shows which is which.
    // The address's label and colour are the ones Receive gave it.
    final rank = {for (var n = 0; n < order.length; n++) order[n]: n};
    final groups = groupCoinsByAddress(utxos);
    List<int> coinsOf(AddressGroup g) =>
        [...g.indices]..sort((a, b) => rank[a]!.compareTo(rank[b]!));
    // Masked under the context that builds the card (the label listener's),
    // not this one: privacy is read where it is drawn.
    String? totalOf(BuildContext context, AddressGroup g) =>
        switch (coinSumText([for (final i in g.indices) utxos[i]])) {
          final sum? => maskAmount(context, sum),
          null => null,
        };
    void labelAddress(String address) =>
        showAddressLabelPrompt(context, address: address);

    Widget row(int i) => CoinRow(
      utxo: utxos[i],
      share: utxoShareOf(utxos[i], totals),
      onTap: () => widget.onToggle(i),
      compact: phone,
      allowPending: widget.allowPending,
      lockFrozen: true,
    );

    // A card per address in every form, its coins inside it.
    Widget group(
      BuildContext context,
      AddressGroup g,
      List<Widget> rows, {
      double rowInset = 0,
    }) => AddressCoinGroup(
      key: ValueKey(g.address ?? ''),
      address: g.address,
      count: g.indices.length,
      total: totalOf(context, g),
      rowInset: rowInset,
      onEditLabel: g.address == null ? null : () => labelAddress(g.address!),
      rows: rows,
    );

    final Widget picker = ListenableBuilder(
      // A label or a colour given here or on Receive lands at once.
      listenable: AddressLabelStore.instance,
      builder: (context, _) {
        if (!_notesView) {
          // The list: an address's coins are the rows under its head.
          return AddressCards(
            children: [
              for (final g in groups)
                group(
                  context,
                  g,
                  [for (final i in coinsOf(g)) row(i)],
                  rowInset: phone ? kPhoneCoinTextInset : CoinColumns.textInset,
                ),
            ],
          );
        }
        if (phone) {
          // A phone has no wall: full-width notes under each address.
          return AddressCards(
            children: [
              for (final g in groups)
                group(context, g, [
                  for (final i in coinsOf(g))
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: note(i),
                    ),
                ]),
            ],
          );
        }
        // The notes: the wall's cards, one per address.
        return AddressCards(
          children: [
            for (final g in groups)
              AddressTray(
                key: ValueKey(g.address ?? ''),
                address: g.address,
                count: g.indices.length,
                total: totalOf(context, g),
                onEditLabel: g.address == null
                    ? null
                    : () => labelAddress(g.address!),
                notes: [for (final i in coinsOf(g)) note(i)],
              ),
          ],
        );
      },
    );

    final Widget body;
    if (phone) {
      body = picker;
    } else {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        child: SingleChildScrollView(child: picker),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                frozenCount > 0
                    ? '${utxos.length} coins · $frozenCount frozen'
                    : '${utxos.length} coins',
                style: AppTypography.body.copyWith(color: s.inkSecondary),
              ),
            ),
            toggle,
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        body,
      ],
    );
  }
}

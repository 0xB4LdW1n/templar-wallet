// The wallet's keys, as a ring — one arc per co-signer, the quorum in the
// centre, and each key's glyph sitting on its own arc. Not a signing
// picture: nothing here has signed, so no seal is drawn.
//
// A multisig's keys are otherwise only ever seen as `[f0b68896/48'/1'/0'/2']
// tpub…` on the wallet-info page. That is the wrong shape for the question
// people actually ask about a shared wallet, which is "whose keys are these,
// and how many of them do we need". The ring answers it in one glance and
// opens the full roster on tap.
//
// Past five keys the circumference stops holding icons legibly, so five are
// drawn and the rest collapse into a "+N" badge; the roster behind it is
// complete either way.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../models/cosigner_label.dart';
import 'app_dialog.dart';
import 'signer_donut.dart';

/// Most icons the ring will draw. Beyond this the remainder becomes "+N".
const int maxRingIcons = 5;

/// One co-signer, resolved for display.
class CosignerEntry {
  const CosignerEntry({
    required this.index,
    required this.key,
    required this.label,
    required this.isLocal,
  });

  /// Position in the wallet's key list — what "Key 3" counts.
  final int index;

  /// `[fingerprint/path]tpub…`.
  final String key;
  final CosignerLabel label;

  /// This app holds the private key and signs with it.
  final bool isLocal;

  String get fingerprint => fingerprintOf(key);
  String get path => pathOf(key);
  String get name => label.displayName(index);

  /// The colour the user gave this key, else the secondary ink. Drawn at
  /// full strength only as the small dot beside the key's name.
  Color colorOn(AppScheme s) => label.color ?? s.inkSecondary;

  /// This key's arc on a ring: the user's colour toned down — several keys
  /// at full strength would turn the ring into a rainbow — or the hairline
  /// ink of a key nobody coloured.
  Color segmentOn(AppScheme s) =>
      label.color?.withValues(alpha: s.isDark ? 0.5 : 0.55) ?? s.edgeStrong;
}

/// Pairs the wallet's keys with whatever they have been called.
List<CosignerEntry> resolveCosigners({
  required List<String> cosignerKeys,
  required Map<String, CosignerLabel> labels,
  List<String> localFingerprints = const [],
}) {
  final local = localFingerprints.map((f) => f.toLowerCase()).toSet();
  return [
    for (var i = 0; i < cosignerKeys.length; i++)
      CosignerEntry(
        index: i,
        key: cosignerKeys[i],
        label:
            labels[cosignerId(cosignerKeys, i)] ??
            CosignerLabel(id: cosignerId(cosignerKeys, i)),
        isLocal: local.contains(fingerprintOf(cosignerKeys[i])),
      ),
  ];
}

/// A transaction's signers as chart slots, named and coloured by the wallet's
/// key labels.
///
/// [signerFingerprints] is the order the transaction lists its signers in;
/// each is paired with the entry of the same fingerprint, when the wallet has
/// one. A fingerprint the wallet does not know still gets a slot, shown by
/// its fingerprint — the chart must never drop a signer the engine reported.
List<SignerSlot> signerSlotsFor({
  required List<CosignerEntry> entries,
  required Iterable<String> signerFingerprints,
  required Iterable<String> signedFingerprints,
}) {
  final byFp = {for (final e in entries) e.fingerprint.toLowerCase(): e};
  final signed = signedFingerprints.map((f) => f.toLowerCase()).toSet();
  return [
    for (final fp in signerFingerprints)
      () {
        final e = byFp[fp.toLowerCase()];
        return SignerSlot(
          id: fp,
          signed: signed.contains(fp.toLowerCase()),
          name: e?.name,
          color: e?.label.color,
          isHardware: e?.label.isHardware ?? false,
          isLocal: e?.isLocal ?? false,
        );
      }(),
  ];
}

/// The mark of a multisig, small: the key ring with one arc of several in
/// the accent — *this* key among the others — and a key in the middle.
///
/// It heads a block that is about joining or forming a multisig, where the
/// full [CosignerRing] has no keys to draw yet. It counts nothing, so it
/// carries no quorum and no seal.
class KeyRingMark extends StatelessWidget {
  const KeyRingMark({super.key, this.size = 40, this.keys = 3});

  final double size;

  /// How many arcs the ring is cut into. The first is this wallet's.
  final int keys;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Semantics(
      label: 'Multisig',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: keyRingPainter(
            colors: [s.accent, for (var i = 1; i < keys; i++) s.edgeStrong],
            strokeFraction: 0.09,
          ),
          child: Center(
            child: Icon(
              Icons.vpn_key_outlined,
              size: size * 0.42,
              color: s.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The ring itself: [entries] drawn around a quorum centre.
///
/// A key is an arc in the hairline ink. A key the user gave a colour draws
/// its arc in that colour, toned down, so a wallet with several coloured
/// keys reads as one ring rather than a rainbow; the colour at full strength
/// belongs to the small dot beside the key's name in the roster. Nothing
/// here is signed, so nothing here is a seal: the glyphs are the keys' own.
class CosignerRing extends StatelessWidget {
  const CosignerRing({
    super.key,
    required this.entries,
    required this.requiredSigs,
    this.size = 132,
    this.onTapEntry,
    this.onTapMore,
  });

  final List<CosignerEntry> entries;

  /// The M of M-of-N, shown in the centre. Zero or null draws the count alone.
  final int? requiredSigs;

  /// Outer side of the whole widget, icons included.
  final double size;

  /// Tapping a drawn icon. Null makes the icons decorative.
  final void Function(CosignerEntry entry)? onTapEntry;

  /// Tapping the "+N" badge, when there is one.
  final VoidCallback? onTapMore;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final total = entries.length;
    if (total == 0) return SizedBox(width: size, height: size);

    // The icons sit ON the ring, so the ring is inset by half an icon to keep
    // them inside the widget's own box.
    const badge = 32.0;
    final ringSize = size - badge;
    final shown = math.min(total, maxRingIcons);
    final overflow = total - shown;
    // The "+N" badge takes the last position on the ring, so a crowded wallet
    // still reads as "these five, and more" rather than as a truncated list.
    final positions = overflow > 0 ? shown + 1 : shown;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: CustomPaint(
              painter: keyRingPainter(
                colors: [for (final e in entries) e.segmentOn(s)],
              ),
              child: Padding(
                padding: EdgeInsets.all(ringSize * 0.2),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          requiredSigs == null
                              ? '$total'
                              : '$requiredSigs of $total',
                          style: AppTypography.balanceMedium.copyWith(
                            color: s.ink,
                          ),
                        ),
                        Text(
                          requiredSigs == null ? 'keys' : 'to sign',
                          style: AppTypography.caption.copyWith(
                            color: s.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          for (var i = 0; i < shown; i++)
            _atAngle(
              slotAngle(i, positions),
              radius: ringSize / 2,
              child: _CosignerBadge(
                entry: entries[i],
                size: badge,
                onTap: onTapEntry == null
                    ? null
                    : () => onTapEntry!(entries[i]),
              ),
            ),
          if (overflow > 0)
            _atAngle(
              slotAngle(shown, positions),
              radius: ringSize / 2,
              child: _MoreBadge(count: overflow, size: badge, onTap: onTapMore),
            ),
        ],
      ),
    );
  }

  /// Centre of slot [i] of [count], measured the way the ring is painted:
  /// from 12 o'clock, clockwise.
  static double slotAngle(int i, int count) =>
      -math.pi / 2 + (2 * math.pi / count) * (i + 0.5);

  Widget _atAngle(
    double angle, {
    required double radius,
    required Widget child,
  }) {
    return Transform.translate(
      offset: Offset(math.cos(angle) * radius, math.sin(angle) * radius),
      child: child,
    );
  }
}

/// One key's glyph, sitting on the ring: the raised surface, a firm
/// hairline, the glyph in the secondary ink.
class _CosignerBadge extends StatelessWidget {
  const _CosignerBadge({required this.entry, required this.size, this.onTap});

  final CosignerEntry entry;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Tooltip(
      message: entry.isLocal ? '${entry.name} · this wallet' : entry.name,
      child: Semantics(
        button: onTap != null,
        label: entry.name,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              // Opaque: the badge sits on the ring's own stroke.
              color: s.panelInset,
              shape: BoxShape.circle,
              border: Border.all(color: s.edgeStrong),
            ),
            child: Icon(
              entry.label.icon,
              size: AppSpacing.iconSmall,
              color: s.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// The keys the ring did not draw.
class _MoreBadge extends StatelessWidget {
  const _MoreBadge({required this.count, required this.size, this.onTap});

  final int count;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Tooltip(
      message: '$count more key${count == 1 ? '' : 's'}',
      child: Semantics(
        button: onTap != null,
        label: '$count more keys',
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: s.panelInset,
              shape: BoxShape.circle,
              border: Border.all(color: s.edgeStrong),
            ),
            child: Center(
              child: Text(
                '+$count',
                style: AppTypography.numericSmall.copyWith(
                  color: s.inkSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── The roster ───────────────────────────────────────────────────────────────

/// The full list of keys, every one of them, with what each is called.
///
/// Rows expand rather than navigate: the key itself is the thing a co-signer
/// asks for, and a sheet that has to be dismissed to read one is a sheet that
/// gets dismissed.
Future<void> showCosignerRoster(
  BuildContext context, {
  required List<CosignerEntry> entries,
  required int? requiredSigs,
  int? initialIndex,
  Future<List<CosignerEntry>?> Function(CosignerEntry entry)? onEdit,
}) {
  return showAppDialog<void>(
    context,
    builder: (_) => AppDialog(
      title: const Text('Keys of this wallet'),
      scrollable: false,
      content: SizedBox(
        width: 460,
        child: _CosignerRosterBody(
          entries: entries,
          requiredSigs: requiredSigs,
          initialIndex: initialIndex,
          onEdit: onEdit,
        ),
      ),
    ),
  );
}

class _CosignerRosterBody extends StatefulWidget {
  const _CosignerRosterBody({
    required this.entries,
    required this.requiredSigs,
    this.initialIndex,
    this.onEdit,
  });

  final List<CosignerEntry> entries;
  final int? requiredSigs;
  final int? initialIndex;

  /// Rename [entry], and hand back the refreshed roster. The sheet holds its
  /// own copy of the list — a rename that only reached the store would leave
  /// the row the user just edited still showing the old name.
  final Future<List<CosignerEntry>?> Function(CosignerEntry entry)? onEdit;

  @override
  State<_CosignerRosterBody> createState() => _CosignerRosterBodyState();
}

class _CosignerRosterBodyState extends State<_CosignerRosterBody> {
  int? _open;
  late List<CosignerEntry> _entries = widget.entries;

  @override
  void initState() {
    super.initState();
    _open = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.requiredSigs != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              'Any ${widget.requiredSigs} of these ${_entries.length} '
              'keys can sign together.',
              style: AppTypography.body.copyWith(color: s.inkSecondary),
            ),
          ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _entries.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, thickness: 1, color: s.edge),
            itemBuilder: (context, i) => _CosignerRow(
              entry: _entries[i],
              expanded: _open == i,
              onTap: () => setState(() => _open = _open == i ? null : i),
              onEdit: widget.onEdit == null
                  ? null
                  : () async {
                      final refreshed = await widget.onEdit!(_entries[i]);
                      if (!mounted || refreshed == null) return;
                      setState(() => _entries = refreshed);
                    },
            ),
          ),
        ),
      ],
    );
  }
}

/// One key in the roster: its glyph on a raised tile, its name (with the
/// user's colour as a dot, when it has one), where it comes from, and the
/// full key on tap.
class _CosignerRow extends StatelessWidget {
  const _CosignerRow({
    required this.entry,
    required this.expanded,
    required this.onTap,
    this.onEdit,
  });

  final CosignerEntry entry;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final dot = entry.label.color;
    return InkWell(
      onTap: onTap,
      hoverColor: s.hover,
      highlightColor: s.pressed,
      splashFactory: NoSplash.splashFactory,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: s.panelInset,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(
                    entry.label.icon,
                    size: AppSpacing.iconSmall,
                    color: s.inkSecondary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (dot != null) ...[
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: dot,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          Flexible(
                            child: Text(
                              entry.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.body.copyWith(
                                color: s.ink,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        entry.fingerprint.isEmpty
                            ? 'Key ${entry.index + 1}'
                            : '${entry.fingerprint} · m/${entry.path}',
                        style: AppTypography.monoSmall.copyWith(
                          color: s.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.isLocal) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: s.panelInset,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                    ),
                    child: Text(
                      'This wallet',
                      style: AppTypography.eyebrow.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  ),
                ],
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Rename',
                    constraints: BoxConstraints.tightFor(
                      width: phone ? AppLayout.minTouchTarget : 32,
                      height: phone ? AppLayout.minTouchTarget : 32,
                    ),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.edit_outlined,
                      size: AppSpacing.iconSmall,
                      color: s.inkSecondary,
                    ),
                    onPressed: onEdit,
                  ),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: AppSpacing.icon,
                  color: s.inkFaint,
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: AppSpacing.md),
              SelectableText(
                entry.key,
                style: AppTypography.monoSmall.copyWith(color: s.inkSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

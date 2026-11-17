import 'package:flutter/material.dart';

import '../../shared/widgets/banners.dart';
import '../../shared/widgets/cards.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../psbt/models/pset_inspection.dart';
import 'models/protocol_link.dart';
import 'models/protocol_review_agreement.dart';
import 'protocol_copy.dart';

/// Human transaction review. The wallet's PSET inspection is authoritative;
/// the site's summary is used only for the explicit agreement check.
///
/// One card of key/value rows — what the user's role is, what leaves, what
/// arrives, what stays locked, what the covenant does, the fee — with every
/// amount in one right-aligned column. Under it, the result of comparing the
/// site's own figures with that reading, said as exactly what was compared.
class ProtocolTransactionReview extends StatelessWidget {
  const ProtocolTransactionReview({
    super.key,
    required this.request,
    required this.inspection,
    required this.agreement,
  });

  final ProtocolRequest request;
  final PsetInspection inspection;
  final ProtocolReviewAgreement agreement;

  @override
  Widget build(BuildContext context) {
    final outgoing = inspection.netChangeLines
        .where((line) => !line.isIncoming)
        .toList();
    final incoming = inspection.netChangeLines
        .where((line) => line.isIncoming)
        .toList();
    final locked = inspection.outputs
        .where((output) => output.isEscrow)
        .toList();
    final role = request.summary?.role ?? '';
    final risk = _riskLines(request);
    final rows = <Widget>[
      _ReviewRow(
        label: 'Your role',
        child: _Values(texts: [ProtocolCopy.english.role(role)]),
      ),
      _ReviewRow(
        label: 'You send',
        child: _Values(
          amounts: [
            for (final line in outgoing)
              _signed(line.displayAmount, incoming: false),
          ],
          empty: 'No net spend from this wallet',
        ),
      ),
      _ReviewRow(
        label: 'You receive',
        child: _Values(
          amounts: [
            for (final line in incoming)
              _signed(line.displayAmount, incoming: true),
          ],
          incoming: true,
          empty: 'No incoming amount in this transaction',
        ),
      ),
      _ReviewRow(
        label: 'Remains locked',
        child: _Values(
          amounts: [
            for (final output in locked)
              if (output.displayAmount != null) output.displayAmount!,
          ],
          texts: [
            for (final output in locked)
              if (output.displayAmount == null) 'Blinded amount',
          ],
          empty: inspection.touchesEscrow
              ? 'No successor covenant output'
              : 'No covenant output',
        ),
      ),
      _ReviewRow(
        label: 'Covenant effect',
        stacked: true,
        child: _Sentence(
          ProtocolCopy.english.covenantEffect(request.action ?? ''),
        ),
      ),
      _ReviewRow(
        label: 'Network fee',
        child: _Values(amounts: [inspection.feeDisplay]),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormCard(
          key: const Key('protocol-human-review'),
          title: 'Transaction review',
          subtitle: 'Amounts below come from Templar Core, not from the site',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: AppScheme.of(context).edge,
                  ),
                rows[i],
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _comparison(context),
        if (risk.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          WarningBanner(
            key: const Key('protocol-risk-warning'),
            title: request.action == 'default'
                ? 'Default and collateral split'
                : 'Missed installment and penalty risk',
            message: risk.join(' · '),
          ),
        ] else if (request.action == 'default' ||
            request.action == 'renewal') ...[
          const SizedBox(height: AppSpacing.lg),
          const DangerBanner(
            key: Key('protocol-risk-missing'),
            title: 'Penalty data missing from the request',
            message:
                'The site did not provide the trigger, m/M, s/S, A(penalty), C(forfeit), C(return) and deadline. The wallet will not invent them.',
          ),
        ],
      ],
    );
  }

  /// The agreement check, said as what it is: the site's figures held
  /// against the wallet's own reading. Matched is a fact with a check, not
  /// a warning; a disagreement names each line; nothing comparable is a
  /// caution, because then only the card above speaks.
  Widget _comparison(BuildContext context) {
    final a = agreement;
    if (!a.canSign) {
      return DangerBanner(
        key: const Key('protocol-summary-mismatch'),
        title: 'Wallet and site do not agree',
        message: a.hasUnverifiedOutputs
            ? 'The transaction contains an output whose commitment the wallet cannot verify. Signing is blocked.'
            : 'Signing is blocked because the wallet inspection is authoritative.',
        action: a.mismatches.isEmpty
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final m in a.mismatches)
                    _MismatchLine(raw: m, walletSees: _walletSees(m)),
                ],
              ),
      );
    }
    if (a.couldCompare) {
      final n = a.checked;
      return _MatchBanner(
        key: const Key('protocol-summary-check'),
        title:
            '$n site amount${n == 1 ? '' : 's'} match${n == 1 ? 'es' : ''} '
            "the wallet's inspection",
        message:
            'Every unambiguous amount in the site summary is the one the '
            'wallet read from the transaction',
      );
    }
    return const WarningBanner(
      key: Key('protocol-summary-check'),
      title: 'No comparable site amount',
      message:
          'The site summary had no unambiguous “You send”, “You receive”, locked collateral or network-fee line. Only the wallet reading above is authoritative.',
    );
  }

  /// What the wallet's own reading holds for the line a mismatch names — the
  /// same four buckets the agreement check sorts site lines into, so the two
  /// figures sit side by side. Display only: the verdict is already made.
  String _walletSees(String mismatch) {
    final label = mismatch.split(':').first.toLowerCase();
    final List<String> values;
    if (label.contains('you receive')) {
      values = [
        for (final l in inspection.netChangeLines)
          if (l.isIncoming) l.displayAmount,
      ];
    } else if (label.contains('you send') || label.contains('you pay')) {
      values = [
        for (final l in inspection.netChangeLines)
          if (!l.isIncoming) l.displayAmount,
      ];
    } else if (label.contains('remains locked') ||
        label.contains('collateral locked')) {
      values = [
        for (final o in inspection.outputs)
          if (o.isEscrow) o.displayAmount ?? 'Blinded amount',
      ];
    } else if (label.contains('network fee')) {
      values = [inspection.feeDisplay];
    } else {
      values = const [];
    }
    return values.isEmpty ? 'Nothing' : values.join(', ');
  }

  static List<String> _riskLines(ProtocolRequest request) {
    if (request.action != 'default' && request.action != 'renewal') {
      return const [];
    }
    final terms = <String>[
      'trigger',
      'miss',
      'penalty',
      'forfeit',
      'return',
      'deadline',
      'block',
      'm/',
      's/',
    ];
    return [
      for (final line
          in request.summary?.lines ?? const <ProtocolSummaryLine>[])
        if (terms.any((term) => line.label.toLowerCase().contains(term)))
          '${line.label}: ${line.amount}',
    ];
  }
}

/// The engine's figure with its direction spelled the way a ledger does: a
/// true minus for what leaves, a plus for what arrives. The digits are the
/// engine's own; only the sign glyph is normalised.
String _signed(String display, {required bool incoming}) {
  final bare = display.trim().replaceFirst(RegExp(r'^[+\-−]\s*'), '');
  return '${incoming ? '+' : '−'}$bare';
}

/// One key/value line of the review: the key in the secondary ink on the
/// left, the value in the right-aligned column. A sentence ([stacked]) takes
/// the full width under its key instead of a ragged right edge.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.label,
    required this.child,
    this.stacked = false,
  });

  final String label;
  final Widget child;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final key = Text(
      label,
      style: AppTypography.bodyOf(context).copyWith(color: s.inkSecondary),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.xxxl),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  key,
                  const SizedBox(height: AppSpacing.xs),
                  child,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: key),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 2, child: child),
                ],
              ),
      ),
    );
  }
}

/// The right-hand column: amounts (tabular, number in ink and unit quiet),
/// plain words, or — when there is nothing — the empty line in the
/// secondary ink.
class _Values extends StatelessWidget {
  const _Values({
    this.amounts = const [],
    this.texts = const [],
    this.incoming = false,
    this.empty = 'Not provided',
  });

  final List<String> amounts;
  final List<String> texts;
  final bool incoming;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final shownAmounts = amounts.where((v) => v.trim().isNotEmpty).toList();
    final shownTexts = texts.where((v) => v.trim().isNotEmpty).toList();
    final style = AppTypography.bodyOf(context);
    if (shownAmounts.isEmpty && shownTexts.isEmpty) {
      return Text(
        empty,
        textAlign: TextAlign.end,
        style: style.copyWith(color: s.inkSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final a in shownAmounts)
          ProtocolFigure(a, color: incoming ? s.success : s.ink),
        for (final t in shownTexts)
          Text(
            t,
            textAlign: TextAlign.end,
            style: style.copyWith(color: s.ink),
          ),
      ],
    );
  }
}

class _Sentence extends StatelessWidget {
  const _Sentence(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTypography.bodyOf(
      context,
    ).copyWith(color: AppScheme.of(context).ink),
  );
}

/// An amount as design.md writes figures: the number in `numeric` and the
/// given ink, its unit beside it one step quieter. A value that does not end
/// in a unit is printed whole.
class ProtocolFigure extends StatelessWidget {
  const ProtocolFigure(
    this.text, {
    super.key,
    this.color,
    this.textAlign = TextAlign.end,
  });

  final String text;
  final Color? color;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final ink = color ?? s.ink;
    final t = text.trim();
    final cut = t.lastIndexOf(' ');
    final unit = cut > 0 ? t.substring(cut + 1) : '';
    final isUnit = unit.isNotEmpty && !RegExp(r'\d').hasMatch(unit);
    final figure = isUnit ? t.substring(0, cut) : t;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: figure,
            style: AppTypography.numeric.copyWith(color: ink),
          ),
          if (isUnit)
            TextSpan(
              text: ' $unit',
              style: AppTypography.caption.copyWith(color: s.inkFaint),
            ),
        ],
      ),
      textAlign: textAlign,
    );
  }
}

/// A disagreement, line by line: what the site claims against what the
/// wallet read for the same line.
class _MismatchLine extends StatelessWidget {
  const _MismatchLine({required this.raw, required this.walletSees});

  /// `"<label>: site says <amount>."`, as the agreement check words it.
  final String raw;
  final String walletSees;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final cut = raw.indexOf(': site says ');
    final label = cut < 0 ? raw : raw.substring(0, cut);
    final site = cut < 0
        ? ''
        : raw
              .substring(cut + ': site says '.length)
              .replaceFirst(RegExp(r'\.$'), '');
    Widget pair(String k, String v) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              k,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          ProtocolFigure(v),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: AppTypography.label.copyWith(color: s.ink)),
          if (site.isNotEmpty) pair('Site says', site),
          pair('Wallet sees', walletSees),
        ],
      ),
    );
  }
}

/// The matched state: the banner's material with a check in the success
/// ink. A comparison that came out right is a fact, so it must not borrow
/// the look of an error.
class _MatchBanner extends StatelessWidget {
  const _MatchBanner({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
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
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_circle_outlined,
              size: AppSpacing.iconSmall,
              color: s.success,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.label.copyWith(color: s.ink)),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message,
                  style: AppTypography.caption.copyWith(color: s.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The head of a request: what is asked (`pageTitle`), who asks and on which
/// network (a 6 px Liquid dot beside the name), and where the answer goes,
/// in mono so a lookalike host is caught character by character.
class ProtocolRequestHeading extends StatelessWidget {
  const ProtocolRequestHeading({
    super.key,
    required this.title,
    this.site,
    this.network,
    this.origin,
    this.walletName,
    this.actions = const [],
  });

  final String title;
  final String? site;

  /// The request's network as the site names it (`liquid-regtest`).
  final String? network;

  /// The connection origin, or the callback host when there is none.
  final String? origin;

  /// The wallet answering, once chosen.
  final String? walletName;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final quiet = AppTypography.caption.copyWith(color: s.inkSecondary);
    final net = network;
    final meta = <InlineSpan>[
      if (site != null) TextSpan(text: site),
      if (site != null && net != null) const TextSpan(text: '  ·  '),
      if (net != null) ...[
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: s.liquid,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
        TextSpan(text: protocolNetworkLabel(net)),
      ],
      if (walletName != null && (site != null || net != null))
        const TextSpan(text: '  ·  '),
      if (walletName != null) TextSpan(text: 'wallet "$walletName"'),
    ];
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.pageTitleOf(context).copyWith(color: s.ink),
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text.rich(TextSpan(children: meta), style: quiet),
        ],
        if (origin != null && origin!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            origin!,
            style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
          ),
        ],
      ],
    );
    return Padding(
      padding: EdgeInsets.only(bottom: phone ? AppSpacing.lg : AppSpacing.xl),
      child: actions.isEmpty
          ? head
          : phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                head,
                const SizedBox(height: AppSpacing.sm),
                Wrap(spacing: AppSpacing.sm, children: actions),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: head),
                const SizedBox(width: AppSpacing.lg),
                Wrap(spacing: AppSpacing.sm, children: actions),
              ],
            ),
    );
  }
}

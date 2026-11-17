import 'package:flutter/material.dart';

import '../../shared/widgets/banners.dart';
import '../../shared/widgets/privacy.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../protocol/models/protocol_portfolio.dart';
import '../protocol/protocol_copy.dart';

/// Human covenant lineage. It renders only nodes supplied by the backend.
///
/// A vertical timeline in the neutral ramp: a hairline spine, one 8 px node
/// per generation — filled ink for what is done, a ring around an ink centre
/// for the current one, a bare ring for what has not happened yet, the
/// danger ink for a default or a missed installment. The outstanding balance
/// at each generation sits right-aligned in one column.
class CovenantTimeline extends StatelessWidget {
  const CovenantTimeline({super.key, required this.loan});

  final ProtocolLoan loan;

  @override
  Widget build(BuildContext context) {
    final nodes = loan.covenant?.nodes ?? const <ProtocolCovenantNode>[];
    if (nodes.isEmpty) {
      return const InfoBanner(
        key: Key('covenant-v1-fallback'),
        title: 'Covenant history not supplied',
        message:
            'Portfolio v1 identifies the loan and transaction ids, but not the covenant generations. The wallet will not reconstruct them from txids.',
      );
    }
    return Semantics(
      label: 'Covenant lifecycle, ${nodes.length} generations',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < nodes.length; index++)
            _CovenantStep(
              node: nodes[index],
              first: index == 0,
              last: index == nodes.length - 1,
            ),
        ],
      ),
    );
  }
}

enum _Node { done, current, upcoming, loss }

class _CovenantStep extends StatelessWidget {
  const _CovenantStep({
    required this.node,
    required this.first,
    required this.last,
  });

  final ProtocolCovenantNode node;
  final bool first;
  final bool last;

  /// Where the 8 px node sits: centred on the title's first line (20 tall).
  static const double _nodeTop = 6;
  static const double _node = 8;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final kind = _kind(node);
    final missed = node.createdBy == 'renewal';
    final label = _label(node);
    final detail = _detail(node);
    final spine = Container(width: 1, color: s.edgeStrong);
    final quiet = AppTypography.caption.copyWith(color: s.inkSecondary);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: AppSpacing.lg,
            child: Column(
              children: [
                SizedBox(height: _nodeTop, child: first ? null : spine),
                _Dot(kind: missed ? _Node.loss : kind),
                Expanded(child: last ? const SizedBox.shrink() : spine),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: AppTypography.bodyOf(
                            context,
                          ).copyWith(color: s.ink),
                        ),
                      ),
                      if (node.balance != null) ...[
                        const SizedBox(width: AppSpacing.md),
                        Amount(
                          node.balance!.display,
                          textAlign: TextAlign.end,
                          style: AppTypography.numeric.copyWith(color: s.ink),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      Text(_statusLabel(node.status), style: quiet),
                      if (missed)
                        Text(
                          'Missed',
                          style: AppTypography.caption.copyWith(
                            color: s.danger,
                          ),
                        ),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          style: AppTypography.caption.copyWith(
                            color: s.inkFaint,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static _Node _kind(ProtocolCovenantNode node) => switch (node.status) {
    'active' || 'current' => _Node.current,
    'pending' || 'cancelled' => _Node.upcoming,
    'defaulted' => _Node.loss,
    _ => _Node.done,
  };

  static String _label(ProtocolCovenantNode node) {
    if (node.isTerminal) {
      return node.status == 'defaulted'
          ? 'Covenant destroyed without successor'
          : 'Terminal covenant spend';
    }
    if (node.isCurrent) return 'Successor covenant active';
    if (node.spentBy != null && node.successorTxid != null) {
      return 'Covenant spent and replaced';
    }
    if (node.spentBy != null) return 'Covenant spent';
    return node.index == 0
        ? 'Root covenant created'
        : 'Covenant generation ${node.index + 1}';
  }

  static String _detail(ProtocolCovenantNode node) {
    final parts = <String>[
      if ((node.createdBy ?? '').isNotEmpty)
        'Created by ${ProtocolCopy.english.action(node.createdBy!).toLowerCase()}',
      if ((node.spentBy ?? '').isNotEmpty)
        'spent by ${ProtocolCopy.english.action(node.spentBy!).toLowerCase()}',
      if (node.successorTxid != null) 'a successor was created',
    ];
    return parts.join(' · ');
  }

  static String _statusLabel(String status) => switch (status) {
    'pending' => 'Pending',
    'active' || 'current' => 'Current',
    'spent' || 'replaced' => 'Replaced',
    'defaulted' => 'Defaulted',
    'repaid' => 'Repaid',
    'returned' => 'Returned',
    'cancelled' => 'Signing cancelled',
    _ => status.replaceAll('_', ' '),
  };
}

class _Dot extends StatelessWidget {
  const _Dot({required this.kind});
  final _Node kind;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    const size = _CovenantStep._node;
    return switch (kind) {
      _Node.done || _Node.loss => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: kind == _Node.loss ? s.danger : s.ink,
          shape: BoxShape.circle,
        ),
      ),
      _Node.current => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: s.ink),
        ),
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: s.ink, shape: BoxShape.circle),
        ),
      ),
      _Node.upcoming => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: s.panel,
          border: Border.all(color: s.edgeStrong),
        ),
      ),
    };
  }
}

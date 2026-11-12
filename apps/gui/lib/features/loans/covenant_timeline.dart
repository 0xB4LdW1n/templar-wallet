import 'package:flutter/material.dart';

import '../../shared/widgets/banners.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../protocol/models/protocol_portfolio.dart';
import '../protocol/protocol_copy.dart';

/// Human covenant lineage. It renders only nodes supplied by the backend.
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

class _CovenantStep extends StatelessWidget {
  const _CovenantStep({
    required this.node,
    required this.first,
    required this.last,
  });

  final ProtocolCovenantNode node;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final tone = _tone(s, node.status);
    final label = _label(node);
    final detail = _detail(node);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                if (!first)
                  Expanded(child: Container(width: 1, color: s.edgeStrong))
                else
                  const Spacer(),
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone.withValues(alpha: 0.15),
                    border: Border.all(color: tone, width: 2),
                  ),
                  child: node.status == 'pending'
                      ? Padding(
                          padding: const EdgeInsets.all(3),
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: tone,
                          ),
                        )
                      : Icon(_icon(node.status), size: 11, color: tone),
                ),
                if (!last)
                  Expanded(child: Container(width: 1, color: s.edgeStrong))
                else
                  const Spacer(),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: AppTypography.body.copyWith(
                            color: s.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TagChip(label: _statusLabel(node.status), color: tone),
                    ],
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: AppTypography.caption.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
        'Spent by ${ProtocolCopy.english.action(node.spentBy!).toLowerCase()}',
      if (node.successorTxid != null) 'A successor was created',
      if (node.balance != null)
        '${node.balance!.display} outstanding at this generation',
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

  static Color _tone(AppScheme s, String status) => switch (status) {
    'pending' => s.inkSecondary,
    'active' || 'current' => s.liquid,
    'spent' || 'replaced' => s.inkFaint,
    'defaulted' => s.danger,
    'repaid' || 'returned' => s.success,
    'cancelled' => s.inkFaint,
    _ => s.warning,
  };

  static IconData _icon(String status) => switch (status) {
    'active' || 'current' => Icons.lock_outline_rounded,
    'spent' || 'replaced' => Icons.arrow_forward_rounded,
    'defaulted' => Icons.warning_amber_rounded,
    'repaid' || 'returned' => Icons.check_rounded,
    'cancelled' => Icons.close_rounded,
    _ => Icons.circle_outlined,
  };
}

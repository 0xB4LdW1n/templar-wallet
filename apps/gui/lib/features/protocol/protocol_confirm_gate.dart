import 'package:flutter/material.dart';

import '../../shared/widgets/buttons.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The explicit-consent step of a Templar Protocol request.
///
/// A signature (or a share of wallet keys) only leaves the wallet after the
/// user has ticked the statement *and* pressed the button — two deliberate
/// acts, so a stray click on a freshly opened window cannot sign a loan.
/// The button stays disabled until the box is ticked; [onConfirm] fires at
/// most once per press. The app-password gate comes after this, in the
/// screen.
///
/// Laid out as the end of a form: the statement as a checkbox row, the
/// reason the button is still off as one caption, then the actions — side by
/// side and right-aligned on desktop, stacked with the primary on top on a
/// phone.
class ProtocolConfirmGate extends StatefulWidget {
  const ProtocolConfirmGate({
    super.key,
    required this.statement,
    required this.buttonLabel,
    required this.onConfirm,
    this.busy = false,
    this.enabled = true,
    this.cancelLabel,
    this.onCancel,
    this.disabledReason,
  });

  /// What the user asserts by ticking the box.
  final String statement;
  final String buttonLabel;
  final VoidCallback onConfirm;

  /// A request is in flight: everything is frozen.
  final bool busy;

  /// False when there is nothing to confirm (e.g. no input of ours to sign).
  final bool enabled;

  /// The way out, as a ghost button beside the primary one. Both must be
  /// given for it to show.
  final String? cancelLabel;
  final VoidCallback? onCancel;

  /// Why the gate is off when [enabled] is false, in one line.
  final String? disabledReason;

  @override
  State<ProtocolConfirmGate> createState() => _ProtocolConfirmGateState();
}

class _ProtocolConfirmGateState extends State<ProtocolConfirmGate> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final canTick = widget.enabled && !widget.busy;
    final canConfirm = widget.enabled && _checked && !widget.busy;
    void toggle() {
      if (canTick) setState(() => _checked = !_checked);
    }

    final reason = !widget.enabled
        ? widget.disabledReason
        : (!_checked && !widget.busy
              ? 'Tick the statement above to continue'
              : null);

    final primary = PrimaryButton(
      key: const Key('protocol-confirm-button'),
      label: widget.buttonLabel,
      isLoading: widget.busy,
      isFullWidth: phone,
      onPressed: canConfirm ? widget.onConfirm : null,
    );
    final cancel = widget.cancelLabel != null && widget.onCancel != null
        ? GhostButton(
            key: const Key('protocol-confirm-cancel'),
            label: widget.cancelLabel!,
            isFullWidth: phone,
            onPressed: widget.busy ? null : widget.onCancel,
          )
        : null;

    return Column(
      // Sized to its content: on a phone it is pinned as the bottom bar.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One row, one target: the box and its words toggle together, at
        // least 48 tall so a thumb lands on it.
        MergeSemantics(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: const Key('protocol-confirm-checkbox'),
              onTap: canTick ? toggle : null,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              hoverColor: s.hover,
              highlightColor: s.pressed,
              splashFactory: NoSplash.splashFactory,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AppLayout.minTouchTarget,
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _checked,
                      onChanged: canTick ? (_) => toggle() : null,
                      // On is the ink, never the accent (design.md,
                      // "Controls").
                      fillColor: WidgetStateProperty.resolveWith(
                        (states) => states.contains(WidgetState.selected)
                            ? s.ink
                            : Colors.transparent,
                      ),
                      checkColor: s.panel,
                      side: BorderSide(color: s.edgeStrong, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusXs,
                        ),
                      ),
                      focusColor: s.hover,
                      hoverColor: Colors.transparent,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        child: Text(
                          widget.statement,
                          style: AppTypography.bodyOf(
                            context,
                          ).copyWith(color: canTick ? s.ink : s.inkSecondary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (reason != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            reason,
            key: const Key('protocol-confirm-reason'),
            textAlign: phone ? TextAlign.start : TextAlign.end,
            style: AppTypography.caption.copyWith(color: s.inkFaint),
          ),
        ],
        SizedBox(height: phone ? AppSpacing.md : AppSpacing.lg),
        if (phone) ...[
          primary,
          if (cancel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            cancel,
          ],
        ] else
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (cancel != null) ...[
                cancel,
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(child: primary),
            ],
          ),
      ],
    );
  }
}

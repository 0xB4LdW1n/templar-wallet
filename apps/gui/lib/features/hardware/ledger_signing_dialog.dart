import 'package:flutter/material.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/seal_mark.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Phases of a hardware signing round-trip.
///
/// When a [verifyTask] is supplied the flow starts at [verifying] (device shows
/// the wallet address) → [verifyConfirm] (user confirms it matches) → [signing].
/// Without it, the flow starts directly at [signing].
enum _SignPhase { verifying, verifyConfirm, signing, broadcasting, done, error }

/// Run [task] (build + sign on device + broadcast) behind a dialog that lists
/// the device's steps. Resolves with the txid on success, or null if the user cancelled.
///
/// If [verifyTask] is given, the dialog first asks the device to display a wallet
/// address and waits for the user to confirm it matches the device screen before
/// signing — a guard that the connected device really controls this wallet.
///
/// [formatError] turns a raw error string into user-facing guidance.
///
/// [signOnly] is the co-signing shape: [task] adds one signature and hands
/// the signed transaction back, nothing is broadcast, and the dialog's words
/// say so — "Signature added", not "Transaction sent".
Future<String?> showLedgerSigningDialog(
  BuildContext context, {
  required Future<String> Function() task,
  Future<String> Function()? verifyTask,
  String Function(String raw)? formatError,
  bool signOnly = false,
}) {
  return showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LedgerSigningDialog(
      task: task,
      verifyTask: verifyTask,
      formatError: formatError,
      signOnly: signOnly,
    ),
  );
}

class LedgerSigningDialog extends StatefulWidget {
  const LedgerSigningDialog({
    super.key,
    required this.task,
    this.verifyTask,
    this.formatError,
    this.signOnly = false,
  });

  final Future<String> Function() task;
  final Future<String> Function()? verifyTask;
  final String Function(String raw)? formatError;

  /// The task signs and returns the transaction; there is no broadcast leg.
  final bool signOnly;

  @override
  State<LedgerSigningDialog> createState() => _LedgerSigningDialogState();
}

class _LedgerSigningDialogState extends State<LedgerSigningDialog> {
  _SignPhase _phase = _SignPhase.signing;
  String? _txid;
  String? _error;
  String? _verifyAddress;

  /// The phase that was running when an error landed — the step the list
  /// marks as failed.
  _SignPhase _failedAt = _SignPhase.signing;

  @override
  void initState() {
    super.initState();
    if (widget.verifyTask != null) {
      _startVerify();
    } else {
      _run();
    }
  }

  /// Ask the device to display a wallet address, then pause for the user to
  /// confirm it matches the device screen before signing.
  Future<void> _startVerify() async {
    setState(() {
      _phase = _SignPhase.verifying;
      _error = null;
    });
    try {
      final addr = await widget.verifyTask!();
      if (!mounted) return;
      setState(() {
        _phase = _SignPhase.verifyConfirm;
        _verifyAddress = addr;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failedAt = _SignPhase.verifying;
        _phase = _SignPhase.error;
        _error = widget.formatError?.call(e.toString()) ?? e.toString();
      });
    }
  }

  Future<void> _run() async {
    setState(() {
      _phase = _SignPhase.signing;
      _error = null;
    });
    try {
      final txid = await widget.task();
      if (!mounted) return;
      if (!widget.signOnly) {
        // Brief broadcasting beat so the success feels sequenced, not instant.
        setState(() => _phase = _SignPhase.broadcasting);
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
      }
      setState(() {
        _phase = _SignPhase.done;
        _txid = txid;
      });
      // Hold the stamped seal briefly, then hand the result back to the
      // caller (the txid and its success screen, or the signed transaction
      // for the quorum chart to take in).
      await Future.delayed(
        Duration(milliseconds: widget.signOnly ? 700 : 1000),
      );
      if (mounted) Navigator.of(context).pop(_txid);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _failedAt = _SignPhase.signing;
        _phase = _SignPhase.error;
        _error = widget.formatError?.call(raw) ?? raw;
      });
    }
  }

  /// The round-trip as a list of steps, each marked against the phase the
  /// dialog is really in.
  List<(String, _StepState)> get _steps {
    final order = <_SignPhase>[
      if (widget.verifyTask != null) ...[
        _SignPhase.verifying,
        _SignPhase.verifyConfirm,
      ],
      _SignPhase.signing,
      if (!widget.signOnly) _SignPhase.broadcasting,
    ];
    final at = switch (_phase) {
      _SignPhase.done => order.length,
      _SignPhase.error => order.indexOf(_failedAt),
      final p => order.indexOf(p),
    };
    String label(_SignPhase p) => switch (p) {
      _SignPhase.verifying => 'Show a wallet address on the device',
      _SignPhase.verifyConfirm => 'Check it matches the device screen',
      _SignPhase.signing => 'Approve on the device',
      _SignPhase.broadcasting => 'Broadcast the transaction',
      _ => '',
    };
    return [
      for (var i = 0; i < order.length; i++)
        (
          label(order[i]),
          i < at
              ? _StepState.done
              : i > at
              ? _StepState.pending
              : _phase == _SignPhase.error
              ? _StepState.failed
              // Waiting on the user's eyes, not on the device: no spinner.
              : order[i] == _SignPhase.verifyConfirm
              ? _StepState.waiting
              : _StepState.current,
        ),
    ];
  }

  /// The device has handed back its signature: the task returned. True for
  /// the broadcast beat as well, which only runs after it.
  bool get _signed =>
      _phase == _SignPhase.done || _phase == _SignPhase.broadcasting;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return AlertDialog(
      title: Text(_title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DeviceSteps(steps: _steps),
            const SizedBox(height: AppSpacing.md),
            if (_signed) ...[
              // The one moment in this dialog that is a signature: the seal,
              // stamped, and nothing else.
              Row(
                children: [
                  const SealMark(
                    stamped: true,
                    size: 32,
                    semanticLabel: 'Signed on device',
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'Signed on device',
                    style: AppTypography.body.copyWith(
                      color: s.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Text(
              _message,
              style: AppTypography.body.copyWith(color: s.inkSecondary),
            ),
            if (_phase == _SignPhase.signing ||
                _phase == _SignPhase.verifying) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Do not disconnect the device',
                style: AppTypography.caption.copyWith(color: s.warning),
              ),
            ],
            if (_phase == _SignPhase.verifyConfirm &&
                _verifyAddress != null) ...[
              const SizedBox(height: AppSpacing.md),
              DataWell(
                child: SelectableText(
                  _verifyAddress!,
                  textAlign: TextAlign.center,
                  style: AppTypography.mono.copyWith(color: s.ink),
                ),
              ),
            ],
            if (_phase == _SignPhase.error && _error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: AppTypography.caption.copyWith(color: s.danger),
              ),
            ],
          ],
        ),
      ),
      actions: _actions,
    );
  }

  String get _title => switch (_phase) {
    _SignPhase.verifying => 'Check your Ledger',
    _SignPhase.verifyConfirm => 'Verify the address',
    _SignPhase.signing =>
      widget.signOnly ? 'Confirm on your device' : 'Confirm on your Ledger',
    _SignPhase.broadcasting => 'Broadcasting…',
    _SignPhase.done => widget.signOnly ? 'Signature added' : 'Transaction sent',
    _SignPhase.error => 'Signing failed',
  };

  String get _message => switch (_phase) {
    _SignPhase.verifying =>
      'Your device is displaying a wallet address. Confirm it on screen.',
    _SignPhase.verifyConfirm =>
      'Does this address exactly match the one shown on your Ledger?',
    _SignPhase.signing =>
      widget.signOnly
          ? 'Check the amounts and addresses on the device screen, then '
                'approve. A Ledger may first ask you to register the wallet '
                'policy — approve that too.'
          : 'Check the amount and address on the device screen, then press '
                'both buttons to approve.',
    _SignPhase.broadcasting => 'Submitting the signed transaction…',
    _SignPhase.done =>
      widget.signOnly
          ? 'The device signed. Its signature is being added to the '
                'transaction.'
          : 'Your transaction was broadcast.',
    _SignPhase.error => 'The device did not complete signing.',
  };

  List<Widget>? get _actions => switch (_phase) {
    _SignPhase.verifying ||
    _SignPhase.signing ||
    _SignPhase.broadcasting ||
    _SignPhase.done => null,
    _SignPhase.verifyConfirm => [
      GhostButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(null),
      ),
      PrimaryButton(label: 'It matches — sign', onPressed: _run),
    ],
    _SignPhase.error => [
      GhostButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(null),
      ),
      PrimaryButton(
        label: 'Retry',
        onPressed: widget.verifyTask != null ? _startVerify : _run,
      ),
    ],
  };
}

enum _StepState { done, current, waiting, pending, failed }

/// A device's steps, one per line: done ones with a neutral check, the live
/// one with a small spinner, one waiting on the user with a ring, a failed one
/// with a cross, the rest in the faint ink.
class _DeviceSteps extends StatelessWidget {
  const _DeviceSteps({required this.steps});

  final List<(String, _StepState)> steps;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, state) in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AppSpacing.iconSmall,
                  height: 20,
                  child: Center(
                    child: switch (state) {
                      _StepState.done => Icon(
                        Icons.check_outlined,
                        size: AppSpacing.iconSmall,
                        color: s.inkSecondary,
                      ),
                      _StepState.current => const SizedBox(
                        width: AppSpacing.md,
                        height: AppSpacing.md,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      _StepState.waiting => Container(
                        width: AppSpacing.sm,
                        height: AppSpacing.sm,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: s.ink, width: 1.5),
                        ),
                      ),
                      _StepState.failed => Icon(
                        Icons.close_outlined,
                        size: AppSpacing.iconSmall,
                        color: s.danger,
                      ),
                      _StepState.pending => Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: s.inkFaint,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.body.copyWith(
                      color: switch (state) {
                        _StepState.done => s.inkSecondary,
                        _StepState.pending => s.inkFaint,
                        _ => s.ink,
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

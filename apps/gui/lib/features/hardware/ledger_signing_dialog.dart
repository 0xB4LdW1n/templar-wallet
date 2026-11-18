import 'package:flutter/material.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/seal_mark.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Phases of a hardware signing round-trip.
///
/// When a [verifyTask] is supplied the flow starts at [verifying] — the
/// device shows a wallet address while this dialog shows the same one, and
/// the user confirms on the device that they match — then [signing].
/// Without it, the flow starts directly at [signing].
enum _SignPhase { verifying, signing, broadcasting, done, error }

/// Run [task] (build + sign on device + broadcast) behind a dialog that lists
/// the device's steps. Resolves with the txid on success, or null if the user cancelled.
///
/// If [verifyTask] is given, the dialog first asks the device to display a
/// wallet address and waits for the user to confirm it there before signing —
/// a guard that the connected device really controls this wallet.
/// [verifyAddress] answers with the address the device is about to show, from
/// the wallet's own descriptor: it is on screen here for as long as it is on
/// the device, which is the only moment the two can be compared. What the
/// device then reports must be that address, or nothing is signed.
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
  Future<String> Function()? verifyAddress,
  String Function(String raw)? formatError,
  bool signOnly = false,
}) {
  return showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LedgerSigningDialog(
      task: task,
      verifyTask: verifyTask,
      verifyAddress: verifyAddress,
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
    this.verifyAddress,
    this.formatError,
    this.signOnly = false,
  });

  final Future<String> Function() task;
  final Future<String> Function()? verifyTask;

  /// The address [verifyTask] will put on the device screen, as this wallet
  /// derives it.
  final Future<String> Function()? verifyAddress;
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

  /// Show the wallet's address here, ask the device to display the same
  /// one, and go on to signing once the user has confirmed it on the device.
  Future<void> _startVerify() async {
    setState(() {
      _phase = _SignPhase.verifying;
      _verifyAddress = null;
      _error = null;
    });
    final String? expected;
    final String shown;
    try {
      expected = await widget.verifyAddress?.call();
      if (!mounted) return;
      setState(() => _verifyAddress = expected);
      shown = await widget.verifyTask!();
      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _failedAt = _SignPhase.verifying;
        _phase = _SignPhase.error;
        _error = widget.formatError?.call(e.toString()) ?? e.toString();
      });
      return;
    }
    // The device derives the address itself. A different one means its keys
    // are not this wallet's, whatever was pressed on it.
    if (expected != null &&
        shown.trim().toLowerCase() != expected.trim().toLowerCase()) {
      setState(() {
        _failedAt = _SignPhase.verifying;
        _phase = _SignPhase.error;
        _error =
            'The device showed $shown, which is not this wallet\'s address '
            '($expected). Nothing was signed.';
      });
      return;
    }
    await _run();
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
      if (widget.verifyTask != null) _SignPhase.verifying,
      _SignPhase.signing,
      if (!widget.signOnly) _SignPhase.broadcasting,
    ];
    final at = switch (_phase) {
      _SignPhase.done => order.length,
      _SignPhase.error => order.indexOf(_failedAt),
      final p => order.indexOf(p),
    };
    String label(_SignPhase p) => switch (p) {
      _SignPhase.verifying => 'Check the address on the device',
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
            // The address stays up for as long as the device shows it: the
            // comparison is made with both in view.
            if (_phase == _SignPhase.verifying && _verifyAddress != null) ...[
              const SizedBox(height: AppSpacing.md),
              DataWell(
                child: SelectableText(
                  _verifyAddress!,
                  textAlign: TextAlign.center,
                  style: AppTypography.mono.copyWith(color: s.ink),
                ),
              ),
            ],
            if (_phase == _SignPhase.signing ||
                _phase == _SignPhase.verifying) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Do not disconnect the device',
                style: AppTypography.caption.copyWith(color: s.warning),
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
    _SignPhase.verifying => 'Check the address',
    _SignPhase.signing =>
      widget.signOnly ? 'Confirm on your device' : 'Confirm on your Ledger',
    _SignPhase.broadcasting => 'Broadcasting…',
    _SignPhase.done => widget.signOnly ? 'Signature added' : 'Transaction sent',
    _SignPhase.error => 'Signing failed',
  };

  String get _message => switch (_phase) {
    _SignPhase.verifying =>
      _verifyAddress == null
          ? 'Your device is showing a wallet address. Confirm it on the '
                'device.'
          : 'Your device is showing a wallet address. Check that it matches '
                'this one, character by character, then confirm on the '
                'device.',
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

enum _StepState { done, current, pending, failed }

/// A device's steps, one per line: done ones with a neutral check, the live
/// one with a small spinner, a failed one with a cross, the rest in the faint
/// ink.
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

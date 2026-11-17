import 'dart:async';
import 'package:flutter/material.dart';
import '../../bridge/bridge_provider.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../services/udev_installer.dart';
import '../create_wallet/models/hw_device.dart';
import 'device_permission_card.dart';
import 'hw_error.dart';
import 'hw_platform.dart';
import 'hwi_install_card.dart';

/// Outcome of the Ledger connect gate.
enum LedgerConnectResult {
  /// Matching device found and confirmed — open the wallet for signing.
  connected,

  /// User chose to open the wallet in watch-only mode (balance + receive only).
  watchOnly,

  /// User backed out.
  cancelled,
}

/// Parse the device fingerprint out of a wallet type label such as
/// `Hardware (1250a3f4)`. Returns null when no fingerprint is embedded.
String? fingerprintFromTypeLabel(String? typeLabel) {
  if (typeLabel == null) return null;
  final match = RegExp(r'\(([0-9a-fA-F]{6,8})\)').firstMatch(typeLabel);
  return match?.group(1);
}

/// Shows the Ledger connect gate. Polls the HWI bridge until a device matching
/// [expectedFingerprint] appears (any device if null), then marks the steps
/// done and resolves with [LedgerConnectResult.connected].
Future<LedgerConnectResult> showLedgerConnectDialog(
  BuildContext context, {
  String? expectedFingerprint,
  Set<String>? expectedFingerprints,
  bool allowWatchOnly = true,
  String title = 'Connect your device',
  String? confirmLabel,
  void Function(HwDevice device)? onDeviceFound,
}) async {
  final result = await showDialog<LedgerConnectResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => LedgerConnectDialog(
      expectedFingerprint: expectedFingerprint,
      expectedFingerprints: expectedFingerprints,
      allowWatchOnly: allowWatchOnly,
      title: title,
      confirmLabel: confirmLabel,
      onDeviceFound: onDeviceFound,
    ),
  );
  return result ?? LedgerConnectResult.cancelled;
}

/// Wait for a device and hand it back, for callers that need to *address* it
/// afterwards rather than just know one is present — co-signing a PSBT, for
/// instance, needs the fingerprint to pass to HWI.
///
/// [expectedFingerprints] accepts any of several devices — a multisig with
/// two hardware keys takes whichever one is plugged in. With [confirmLabel]
/// the gate does not close itself on a match: it names the device and waits
/// for the user to press the button, so the next step (approving on the
/// device) is taken deliberately rather than sprung.
Future<HwDevice?> showHwDevicePickerDialog(
  BuildContext context, {
  String? expectedFingerprint,
  Set<String>? expectedFingerprints,
  String title = 'Connect the signing device',
  String? confirmLabel,
}) async {
  HwDevice? found;
  final result = await showLedgerConnectDialog(
    context,
    expectedFingerprint: expectedFingerprint,
    expectedFingerprints: expectedFingerprints,
    // There is no watch-only answer to "which device signs this?".
    allowWatchOnly: false,
    title: title,
    confirmLabel: confirmLabel,
    onDeviceFound: (d) => found = d,
  );
  return result == LedgerConnectResult.connected ? found : null;
}

/// User's intent when opening a hardware wallet from the picker.
enum HwOpenChoice {
  /// Connect the device now and open for signing.
  connect,

  /// Open in watch-only mode (balance + receive only, no device).
  watchOnly,

  /// Backed out.
  cancelled,
}

/// Choice-first gate shown when a hardware wallet is selected: connect the
/// device now, or open watch-only. Returns [HwOpenChoice.cancelled] if dismissed.
Future<HwOpenChoice> showHwOpenChoiceDialog(
  BuildContext context, {
  required String walletName,
}) async {
  final result = await showDialog<HwOpenChoice>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text('Open "$walletName"'),
        content: SizedBox(
          width: 400,
          child: ListCard(
            children: [
              ListRow(
                icon: Icons.usb_outlined,
                title: 'Connect device',
                subtitle: 'Plug in your hardware wallet to sign and send',
                chevron: true,
                onTap: () => Navigator.of(ctx).pop(HwOpenChoice.connect),
              ),
              ListRow(
                icon: Icons.visibility_outlined,
                title: 'Open watch-only',
                subtitle: 'View balance and receive. No device needed',
                chevron: true,
                onTap: () => Navigator.of(ctx).pop(HwOpenChoice.watchOnly),
              ),
            ],
          ),
        ),
        actions: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(HwOpenChoice.cancelled),
          ),
        ],
      );
    },
  );
  return result ?? HwOpenChoice.cancelled;
}

class LedgerConnectDialog extends StatefulWidget {
  const LedgerConnectDialog({
    super.key,
    this.expectedFingerprint,
    this.expectedFingerprints,
    this.allowWatchOnly = true,
    this.title = 'Connect your device',
    this.confirmLabel,
    this.onDeviceFound,
  });

  final String? expectedFingerprint;

  /// Any of these devices will do. Combined with [expectedFingerprint]; both
  /// null accepts whatever answers.
  final Set<String>? expectedFingerprints;
  final bool allowWatchOnly;
  final String title;

  /// When set, a matched device is shown with this button instead of the
  /// dialog closing on its own; pressing it resolves `connected`.
  final String? confirmLabel;

  /// Fired with the matched device just before the dialog resolves.
  final void Function(HwDevice device)? onDeviceFound;

  /// Every fingerprint that satisfies the gate, lower-cased. Empty = any.
  Set<String> get wanted => {
    if (expectedFingerprint != null) expectedFingerprint!.toLowerCase(),
    ...?expectedFingerprints?.map((f) => f.toLowerCase()),
  };

  @override
  State<LedgerConnectDialog> createState() => _LedgerConnectDialogState();
}

class _LedgerConnectDialogState extends State<LedgerConnectDialog> {
  final _bridge = walletBridge;
  Timer? _poll;
  bool _found = false;
  String? _error;
  HwDevice? _device;

  /// HWI binary missing — polling is paused and the install card shown.
  bool _hwiMissing = false;

  /// The OS is refusing device access (Linux udev) — polling is paused and
  /// the permission card shown. Polling on would spawn a subprocess every
  /// 1.5 s for a condition that cannot resolve itself.
  bool _permissionBlocked = false;
  String? _permissionDetail;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  /// True while an identify is in flight. Opening a device is slow — an `hwi
  /// enumerate` unpacks itself on every run, and a Jade waits for a PIN — so
  /// without this the timer stacks up overlapping attempts that fight over the
  /// same USB handle, which looks exactly like a flaky device.
  bool _scanInFlight = false;

  /// Whether anything wallet-shaped is plugged in, from the cheap detection
  /// that reads cached USB descriptors and never opens a device.
  bool _devicePresent = false;

  /// An identify attempt already ran for the currently attached device. Set so
  /// the timer does not keep re-opening it: on a Jade every attempt is another
  /// PIN prompt, and the old 2-second loop turned a wrong-device or
  /// declined-unlock into an endless series of them.
  bool _identifyAttempted = false;

  /// Detection ticks that saw nothing, for the slow HWI sweep below.
  int _emptyTicks = 0;

  void _startPolling() {
    _poll?.cancel();
    _identifyAttempted = false;
    _detectOnce();
    // Presence only. The expensive step — opening the device to read its
    // fingerprint — is triggered once per attached device, below.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _detectOnce());
  }

  /// Cheap: "is something plugged in?", asked of USB descriptors the OS already
  /// cached. Safe on a timer because it never talks to the device.
  Future<void> _detectOnce() async {
    if (_found || _hwiMissing || _permissionBlocked || !mounted) return;
    try {
      final detected = await _bridge.enumerateNativeDevices();
      if (!mounted) return;
      // Usable, not merely native-drivable: on Windows and Linux a Trezor or a
      // Coldcard is paired through the HWI helper, and gating on the native
      // driver alone would leave those users watching a spinner for a device
      // sitting right there.
      final present =
          detected.any((d) => d.drivable) ||
          (detected.isNotEmpty && hwiFallbackUsable);
      // A device unplugged and plugged back in deserves a fresh attempt —
      // reconnecting is exactly how a user retries.
      if (!present && _identifyAttempted) _identifyAttempted = false;
      if (present != _devicePresent) setState(() => _devicePresent = present);
      if (present && !_identifyAttempted && !_scanInFlight) {
        _identify();
        return;
      }
      // Nothing recognised on the bus, but the helper can still run: it knows
      // devices our own USB id table does not, so give it an occasional turn.
      // Slow (~16 s) because each attempt spawns a subprocess — and safe,
      // because this branch only runs when no device we could open was seen,
      // so it can never sit on a Jade's PIN prompt.
      _emptyTicks++;
      if (!present && hwiFallbackUsable && _emptyTicks % 8 == 0) {
        _identifyAttempted = false;
        _identify();
      }
    } catch (_) {
      // Detection is the cheap half; a failure here must not close the gate.
      // The identify path below reports anything that actually matters.
    }
  }

  /// Expensive: open the attached devices and read their master fingerprints.
  /// On a Jade this prompts for the PIN, so it runs once per attached device
  /// and then waits for the user.
  Future<void> _identify() async {
    if (_found ||
        _hwiMissing ||
        _permissionBlocked ||
        _scanInFlight ||
        !mounted) {
      return;
    }
    _scanInFlight = true;
    _identifyAttempted = true;
    setState(() {});
    try {
      await _scanOnceInner();
    } finally {
      _scanInFlight = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _scanOnceInner() async {
    try {
      final devices = await _bridge.enumerateHwDevices();
      if (!mounted || _found) return;
      final wanted = widget.wanted;
      final match = devices.where((d) {
        if (wanted.isEmpty) return true;
        return wanted.contains(d.fingerprint.toLowerCase());
      });
      if (match.isNotEmpty) {
        setState(() => _error = null);
        _onFound(match.first);
        return;
      }
      // A device answered, but not this wallet's device. Worth saying which:
      // with two devices on the desk the fix is to swap cables, and silence
      // here used to look identical to "still searching".
      setState(
        () => _error = devices.isEmpty
            ? null
            : wanted.length > 1
            ? 'Connected device ${devices.first.fingerprint} is not one of '
                  'this wallet\'s hardware keys (${wanted.join(', ')}). '
                  'Connect one of those and press Retry.'
            : 'Connected device ${devices.first.fingerprint} is not the one '
                  'this wallet was created from (${wanted.join()}). '
                  'Connect that device and press Retry.',
      );
    } catch (e) {
      if (!mounted) return;
      final failure = classifyHwError(e);
      if (failure.isHwiMissing) {
        // Missing toolkit is fixable in place — pause polling (each failing
        // attempt spawns a subprocess) and offer the installer.
        _poll?.cancel();
        setState(() {
          _hwiMissing = true;
          _error = null;
        });
      } else if (failure.isPermission && UdevInstaller.supported) {
        _poll?.cancel();
        setState(() {
          _permissionBlocked = true;
          _permissionDetail = failure.message;
          _error = null;
        });
      } else {
        // Transient device issue — surface it but keep polling.
        setState(() => _error = failure.message);
      }
    }
  }

  void _onFound(HwDevice device) {
    _found = true;
    _poll?.cancel();
    widget.onDeviceFound?.call(device);
    setState(() => _device = device);
    // With a confirm button the gate waits for the user: the next step is
    // an approval on the device, which nobody wants sprung on them.
    if (widget.confirmLabel != null) return;
    // Hold the finished step list briefly so the confirmation is visible.
    Timer(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.of(context).pop(LedgerConnectResult.connected);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No platform wall here any more — the scan reaches a Ledger or a Jade on
    // every OS. A device with no path on this platform surfaces through the
    // normal error state, with the reason on it.
    if (_hwiMissing) {
      return AlertDialog(
        title: const Text('HWI toolkit required'),
        content: SizedBox(
          width: 460,
          child: HwiInstallCard(
            onInstalled: () {
              setState(() => _hwiMissing = false);
              _startPolling();
            },
          ),
        ),
        actions: [
          GhostButton(
            label: 'Cancel',
            onPressed: () =>
                Navigator.of(context).pop(LedgerConnectResult.cancelled),
          ),
        ],
      );
    }
    if (_permissionBlocked) {
      return AlertDialog(
        title: const Text('Device access blocked'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: DevicePermissionCard(
              detail: _permissionDetail,
              onFixed: () {
                setState(() {
                  _permissionBlocked = false;
                  _permissionDetail = null;
                });
                _startPolling();
              },
            ),
          ),
        ),
        actions: [
          GhostButton(
            label: 'Cancel',
            onPressed: () =>
                Navigator.of(context).pop(LedgerConnectResult.cancelled),
          ),
          if (widget.allowWatchOnly)
            GhostButton(
              label: 'Open in watch-only',
              onPressed: () =>
                  Navigator.of(context).pop(LedgerConnectResult.watchOnly),
            ),
        ],
      );
    }

    final s = AppScheme.of(context);
    final device = _device;
    final error = _error;
    // What the gate is waiting for, as a list the user can follow: plugged
    // in, unlocked, read. The current step carries a spinner because the
    // gate is live — it keeps watching the bus until something answers.
    final steps = <(String, _StepState)>[
      (
        'Plug in the device with its cable',
        _found || _devicePresent ? _StepState.done : _StepState.current,
      ),
      (
        'Unlock it with your PIN — on a Ledger, open the Bitcoin Testnet app',
        _found
            ? _StepState.done
            : (_devicePresent && !_scanInFlight)
            ? _StepState.current
            : _StepState.pending,
      ),
      (
        'Read the device',
        _found
            ? _StepState.done
            : _scanInFlight
            ? _StepState.current
            : _StepState.pending,
      ),
    ];

    return AlertDialog(
      title: Text(_found ? 'Device connected' : widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DeviceSteps(steps: steps),
            if (_found && device != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: s.panelInset,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        device.model,
                        style: AppTypography.body.copyWith(
                          color: s.ink,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      device.fingerprint,
                      style: AppTypography.mono.copyWith(color: s.inkSecondary),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _Dot(s.success),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Ready',
                      style: AppTypography.caption.copyWith(color: s.ink),
                    ),
                  ],
                ),
              ),
              if (widget.confirmLabel != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Press “${widget.confirmLabel}”, then approve the '
                  'transaction on the device screen.',
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ],
            ],
            if (error != null && !_found) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                error,
                style: AppTypography.caption.copyWith(color: s.danger),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
      actions: _found
          ? (widget.confirmLabel == null
                ? null
                : [
                    GhostButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(LedgerConnectResult.cancelled),
                    ),
                    PrimaryButton(
                      label: widget.confirmLabel!,
                      icon: Icons.draw_outlined,
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(LedgerConnectResult.connected),
                    ),
                  ])
          : [
              GhostButton(
                label: 'Cancel',
                onPressed: () =>
                    Navigator.of(context).pop(LedgerConnectResult.cancelled),
              ),
              if (widget.allowWatchOnly)
                GhostButton(
                  label: 'Open in watch-only',
                  onPressed: () =>
                      Navigator.of(context).pop(LedgerConnectResult.watchOnly),
                ),
              // The device is opened once per connection, not on a loop: on a
              // Jade each attempt is another PIN prompt. After a declined or
              // timed-out unlock, retrying is the user's call.
              if (_devicePresent)
                SecondaryButton(
                  label: _identifyAttempted ? 'Retry' : 'Check device',
                  onPressed: _scanInFlight ? null : _identify,
                ),
            ],
    );
  }
}

enum _StepState { done, current, pending }

/// A device's steps, one per line: done ones with a neutral check, the
/// current one with a small spinner, the rest in the faint ink.
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
                      _StepState.pending => _Dot(s.inkFaint),
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
                        _StepState.current => s.ink,
                        _StepState.pending => s.inkFaint,
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

/// 6 px dot.
class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
  );
}

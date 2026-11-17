// The list of connected hardware wallets, as its own block.
//
// # Why this is separate from the warnings around it
//
// The USB step used to render prerequisites, platform limits, permission fixes
// and the device list as one column of cards, and the same device could appear
// twice: once in the "connected and recognised" list inside a warning card, and
// again in the scan results below it. Which row to click was a guess.
//
// Here the devices are one section with one row per physical device, and every
// warning lives outside it.
//
// # Two questions, two costs
//
// *What is plugged in?* is answered by reading USB descriptors the OS already
// cached: instant, safe to repeat, and it never touches the device. That runs on
// a timer so the section reacts to a cable being connected.
//
// *Which wallet does it hold?* means opening the device and asking for a key —
// which prompts for the PIN on a Jade and takes exclusive hold of its port. That
// only ever happens when the user asks for it.
//
// So a row starts as "Jade — connected" and becomes "Jade — a1b2c3d4" after
// identification. Rows are keyed by the USB path, which is also what the
// backend reports for a natively-driven device, so the two answers land on the
// same row instead of producing two.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../bridge/bridge_provider.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/choice_list.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../create_wallet/models/hw_device.dart';
import '../create_wallet/models/native_device.dart';
import 'hw_error.dart';
import 'hw_platform.dart';

/// One physical device, with whatever is known about it so far.
class DeviceRow {
  const DeviceRow({
    required this.model,
    required this.transport,
    required this.path,
    required this.drivable,
    this.family = '',
    this.usbId,
    this.device,
  });

  final String model;

  /// "hid" or "serial".
  final String transport;
  final String path;

  /// Whether a **native** driver exists for this family (Ledger, Jade).
  ///
  /// Not the same as usable: see [usable]. A Trezor is not drivable and is
  /// perfectly usable on Windows and Linux, through the HWI helper.
  final bool drivable;

  /// Protocol family as the backend names it ("jade", "ledger", …). Empty when
  /// the row came from a scan result, which reports a model rather than a family.
  final String family;
  final String? usbId;

  /// Set once the device has been opened and its master fingerprint read.
  /// Until then the row is a detection, not a wallet.
  final HwDevice? device;

  bool get isIdentified => device != null;
  String? get fingerprint => device?.fingerprint;

  /// Whether this device can be paired **here**, by either route: a native
  /// driver, or the HWI helper where it can run.
  ///
  /// The two are not the same, and conflating them greys out every Trezor,
  /// Coldcard, KeepKey and BitBox on Windows and Linux — where they work fine.
  /// Only macOS, which cannot start the helper at all, is left with the
  /// native families.
  bool get usable => drivable || hwiFallbackUsable;

  /// Whether this device can hold a Liquid wallet. Jade only — every other
  /// family is Bitcoin-only in firmware, so a Liquid wallet paired with one
  /// could receive funds it could never spend.
  bool get supportsLiquid {
    final haystack = '$family $model'.toLowerCase();
    return haystack.contains('jade');
  }
}

/// Fold the cheap detection list and the identified-device list into one row
/// per physical device.
///
/// A natively driven device reports the same USB path in both answers, which is
/// what keeps it to a single row. A device reached through the HWI helper has a
/// path of its own shape and no detection entry to merge with, so it is
/// appended — still once.
List<DeviceRow> mergeDeviceRows({
  required List<NativeDevice> detected,
  required List<HwDevice> identified,
}) {
  final byPath = {for (final d in identified) d.path: d};
  final claimed = <String>{};

  final rows = <DeviceRow>[
    for (final d in detected)
      DeviceRow(
        model: d.model,
        transport: d.transport,
        path: d.path,
        drivable: d.drivable,
        family: d.family,
        usbId: d.usbId,
        device: () {
          final match = byPath[d.path];
          if (match != null) claimed.add(match.path);
          return match;
        }(),
      ),
  ];

  for (final d in identified) {
    if (claimed.contains(d.path)) continue;
    // Same device on a different path shape (HWI reports its own): match on
    // the fingerprint so it cannot be listed a second time.
    if (rows.any((r) => r.fingerprint == d.fingerprint)) continue;
    rows.add(
      DeviceRow(
        model: d.model,
        transport: d.path.startsWith('/dev/') ? 'serial' : 'hid',
        path: d.path,
        drivable: true,
        device: d,
      ),
    );
  }
  return rows;
}

class DeviceListSection extends StatefulWidget {
  const DeviceListSection({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.liquidWanted,
    this.onFailure,
  });

  /// Currently chosen device, by fingerprint.
  final HwDevice? selected;
  final void Function(HwDevice) onSelect;

  /// Whether the wizard asked for Liquid — drives the per-row capability chip,
  /// so a Bitcoin-only device is called out before it is chosen rather than
  /// after.
  final bool liquidWanted;

  /// Failures that have a fix elsewhere on the screen (install HWI, repair
  /// permissions) are handed up instead of shown here.
  final void Function(HwFailure)? onFailure;

  @override
  State<DeviceListSection> createState() => _DeviceListSectionState();
}

class _DeviceListSectionState extends State<DeviceListSection> {
  final _bridge = walletBridge;

  List<NativeDevice> _detected = const [];
  List<HwDevice> _identified = const [];
  Timer? _detectTimer;
  bool _identifying = false;
  bool _detectedOnce = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detect();
    // Detection reads cached USB descriptors — no device is opened, so this can
    // run on a timer without prompting anyone for a PIN.
    _detectTimer = Timer.periodic(const Duration(seconds: 3), (_) => _detect());
  }

  @override
  void dispose() {
    _detectTimer?.cancel();
    super.dispose();
  }

  Future<void> _detect() async {
    try {
      final devices = await _bridge.enumerateNativeDevices();
      if (!mounted) return;
      setState(() {
        _detected = devices;
        _detectedOnce = true;
      });
    } catch (_) {
      // Detection is the cheap half and never the whole answer — a failure
      // here must not blank the rows already on screen.
      if (mounted) setState(() => _detectedOnce = true);
    }
  }

  /// Open the attached devices and read their fingerprints. This is the step
  /// that prompts for the PIN on a Jade, so it only runs when asked.
  Future<void> _identify() async {
    setState(() {
      _identifying = true;
      _error = null;
    });
    try {
      final devices = await _bridge.enumerateHwDevices();
      if (!mounted) return;
      setState(() {
        _identified = devices;
        _identifying = false;
      });
      // One device and nothing chosen yet: choosing it for the user is safe
      // and saves a click. With two attached, the choice is theirs.
      if (devices.length == 1 && widget.selected == null) {
        widget.onSelect(devices.first);
      }
    } catch (e) {
      if (!mounted) return;
      final failure = classifyHwError(e);
      setState(() {
        _identifying = false;
        // Anything with a fix card of its own is handed up; what is left is a
        // message about this device, and belongs next to the device.
        _error = (failure.isHwiMissing || failure.isPermission)
            ? null
            : failure.message;
      });
      if (failure.isHwiMissing || failure.isPermission) {
        widget.onFailure?.call(failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final rows = mergeDeviceRows(detected: _detected, identified: _identified);
    final anyUnidentified = rows.any((r) => r.usable && !r.isIdentified);
    // Where the HWI helper runs, it is also the catch-all for a device our own
    // USB table does not recognise — so identification stays offered even when
    // detection found nothing, or a brand-new model could never be paired.
    final canIdentify = rows.any((r) => r.usable) || hwiFallbackUsable;
    final error = _error;

    // One card: a header row with the count and the one action that talks
    // to the devices, then one row per physical device.
    return ListCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kListPad,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  rows.isEmpty
                      ? 'Connected devices'
                      : 'Connected devices · ${rows.length}',
                  style: AppTypography.label.copyWith(color: s.inkSecondary),
                ),
              ),
              if (_identifying)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: AppSpacing.md,
                        height: AppSpacing.md,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Identifying',
                        style: AppTypography.caption.copyWith(
                          color: s.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                GhostButton(
                  onPressed: canIdentify ? _identify : _detect,
                  icon: anyUnidentified
                      ? Icons.fingerprint_outlined
                      : Icons.refresh_outlined,
                  label: anyUnidentified ? 'Identify' : 'Refresh',
                ),
            ],
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kListPad,
              vertical: AppSpacing.lg,
            ),
            child: Text(
              _detectedOnce
                  ? 'Nothing connected yet. Plug in your device with its '
                        'cable — this list updates on its own.'
                  : 'Looking for devices…',
              style: AppTypography.body.copyWith(color: s.inkSecondary),
            ),
          )
        else
          for (final row in rows)
            _DeviceRowTile(
              row: row,
              isSelected:
                  row.fingerprint != null &&
                  row.fingerprint == widget.selected?.fingerprint,
              liquidWanted: widget.liquidWanted,
              busy: _identifying,
              onTap: () {
                final device = row.device;
                if (device != null) {
                  widget.onSelect(device);
                } else if (row.usable && !_identifying) {
                  _identify();
                }
              },
            ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: kListPad,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 20,
                  child: Icon(
                    Icons.error_outline,
                    size: AppSpacing.iconSmall,
                    color: s.danger,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    error,
                    style: AppTypography.caption.copyWith(color: s.danger),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One device: its radio (or a block mark when it cannot be used here), the
/// model, what it can hold, its state, and how it is attached.
class _DeviceRowTile extends StatefulWidget {
  const _DeviceRowTile({
    required this.row,
    required this.isSelected,
    required this.liquidWanted,
    required this.busy,
    required this.onTap,
  });

  final DeviceRow row;
  final bool isSelected;
  final bool liquidWanted;
  final bool busy;
  final VoidCallback onTap;

  @override
  State<_DeviceRowTile> createState() => _DeviceRowTileState();
}

class _DeviceRowTileState extends State<_DeviceRowTile> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final row = widget.row;
    final usable = row.usable;
    final enabled = usable && !widget.busy;

    final (Color dot, String word) = row.isIdentified
        ? (s.success, 'Ready')
        : usable
        ? (s.success, 'Connected')
        : (s.warning, 'Not usable here');

    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      color: enabled && _hover ? s.hover : Colors.transparent,
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      constraints: const BoxConstraints(minHeight: AppSpacing.rowHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          // Selection affordance: a real radio for the devices that can be
          // chosen, a block mark for the ones that cannot. Centred in the
          // list's icon column so the text lines up with the header.
          SizedBox(
            width: kListTile,
            child: Center(
              child: usable
                  ? OptionRadio(selected: widget.isSelected)
                  : Icon(
                      Icons.block_outlined,
                      size: AppSpacing.icon,
                      color: s.inkFaint,
                    ),
            ),
          ),
          const SizedBox(width: kListGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyOf(context).copyWith(
                          fontWeight: FontWeight.w500,
                          color: usable ? s.ink : s.inkFaint,
                        ),
                      ),
                    ),
                    // What this device can hold, said before it is chosen —
                    // with a warning dot when the wizard asked for Liquid and
                    // this device cannot carry it.
                    if (usable) ...[
                      const SizedBox(width: AppSpacing.sm),
                      QuietTag(
                        label: row.supportsLiquid ? 'BTC + Liquid' : 'BTC only',
                        dot: !row.supportsLiquid && widget.liquidWanted
                            ? s.warning
                            : null,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _subtitle(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: dot,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(word, style: AppTypography.caption.copyWith(color: s.ink)),
            ],
          ),
        ],
      ),
    );

    return Semantics(
      button: usable,
      selected: widget.isSelected,
      enabled: enabled,
      child: MergeSemantics(
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
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? widget.onTap : null,
            child: body,
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final row = widget.row;
    final parts = <String>[];
    if (row.isIdentified) {
      parts.add('fingerprint ${row.fingerprint}');
    } else if (row.usable) {
      // Worth naming the slower route, because it is the one that asks for an
      // install and takes seconds rather than milliseconds.
      parts.add(
        row.drivable ? 'select to identify' : 'select to identify via HWI',
      );
    } else {
      parts.add('needs the HWI helper — $hwiUnavailableHere');
    }
    if (row.usbId != null) parts.add(row.usbId!);
    parts.add(row.transport);
    return parts.join(' · ');
  }
}

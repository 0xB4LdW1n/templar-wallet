// The last step of a hardware pairing: what was read from the device, and
// which checks the code ran on it.
//
// A wallet built from a device is the one setup where "it seemed to work" is
// not good enough. The device holds the keys, so a wallet whose descriptor came
// from somewhere else is a wallet that can receive funds and never spend them —
// and nothing on a dashboard would show it. This screen states, per network,
// what exists and where it came from, and lists the checks that ran.
//
// It also has to be honest when half the pairing failed: a Jade that gave up
// its Bitcoin descriptors but not its Liquid one leaves a real, usable Bitcoin
// wallet, and saying so beats both a green tick and an error page.

import 'package:flutter/material.dart';

import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// One network's outcome in the recap.
class PairingNetwork {
  const PairingNetwork({
    required this.name,
    required this.icon,
    required this.color,
    required this.ok,
    required this.detail,
    this.descriptor,
    this.action,
    this.actionLabel,
    this.busy = false,
  });

  final String name;
  final IconData icon;
  final Color color;

  /// Whether this side of the wallet exists and is usable.
  final bool ok;

  /// One line on what it is, or why it is missing.
  final String detail;

  /// The descriptor stored for this side, shown so the user can compare it with
  /// their device or keep it as a backup.
  final String? descriptor;

  /// Offered when a side is missing and there is something to press — "retry
  /// Liquid", typically.
  final VoidCallback? action;
  final String? actionLabel;
  final bool busy;
}

/// A named check that was performed, and its result.
class PairingCheck {
  const PairingCheck({required this.label, required this.passed, this.detail});
  final String label;
  final bool passed;
  final String? detail;
}

class PairingRecapView extends StatelessWidget {
  const PairingRecapView({
    super.key,
    required this.walletName,
    required this.deviceLabel,
    required this.fingerprint,
    required this.networks,
    required this.checks,
    this.footnote,
  });

  final String walletName;

  /// "Blockstream Jade over USB", "SeedSigner (air-gap, QR)".
  final String deviceLabel;

  /// Master fingerprint the wallet is bound to. Empty hides the chip.
  final String fingerprint;

  final List<PairingNetwork> networks;
  final List<PairingCheck> checks;

  /// Extra line under the checks — what happens at signing time, typically.
  final String? footnote;

  bool get _allOk =>
      networks.every((n) => n.ok) && checks.every((c) => c.passed);

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    // A plain Column, not a scroll view: every caller places this inside
    // StepFlowScaffold, which already scrolls its body. A second viewport there
    // gets unbounded height and throws.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Headline: a success dot only when everything asked for is there.
        Row(
          children: [
            _Dot(_allOk ? s.success : s.warning),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                _allOk ? 'Pairing complete' : 'Paired, with one part missing',
                style: AppTypography.sectionTitle.copyWith(color: s.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '$walletName · $deviceLabel',
          style: AppTypography.body.copyWith(color: s.inkSecondary),
        ),
        if (fingerprint.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _Panel(
            child: _KeyValue(
              label: 'Fingerprint',
              child: Text(
                fingerprint,
                style: AppTypography.mono.copyWith(color: s.ink),
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        for (final n in networks) ...[
          _NetworkResultCard(network: n),
          const SizedBox(height: AppSpacing.md),
        ],
        if (checks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Checks',
            style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final c in checks)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: AppSpacing.md,
                    height: 20,
                    child: Center(child: _Dot(c.passed ? s.success : s.danger)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: c.label,
                        style: AppTypography.body.copyWith(
                          color: c.passed ? s.inkSecondary : s.danger,
                        ),
                        children: [
                          if (c.detail != null)
                            TextSpan(
                              text: '  ${c.detail}',
                              style: AppTypography.monoSmall.copyWith(
                                color: s.inkFaint,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (footnote != null) ...[
          const SizedBox(height: AppSpacing.lg),
          InfoBanner(message: footnote!),
        ],
      ],
    );
  }
}

/// What was read for one network: whether that side exists, the account it
/// sits at, and the descriptor as stored.
class _NetworkResultCard extends StatelessWidget {
  const _NetworkResultCard({required this.network});
  final PairingNetwork network;

  /// The account path inside a descriptor's key origin,
  /// `wpkh([deadbeef/84h/1h/0h]tpub…)` → `m/84h/1h/0h`. Display only.
  static String? _derivation(String descriptor) {
    final match = RegExp(r'\[[0-9a-fA-F]{8}(/[^\]]+)\]').firstMatch(descriptor);
    return match == null ? null : 'm${match.group(1)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final n = network;
    final descriptor = n.descriptor;
    final derivation = descriptor == null ? null : _derivation(descriptor);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The chain's hue on its glyph only — never on the card.
              ListIconTile(icon: n.icon, tint: n.color),
              const SizedBox(width: kListGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.name,
                      style: AppTypography.bodyOf(
                        context,
                      ).copyWith(fontWeight: FontWeight.w500, color: s.ink),
                    ),
                    Text(
                      n.detail,
                      style: AppTypography.caption.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Dot(n.ok ? s.success : s.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    n.ok ? 'Paired' : 'Missing',
                    style: AppTypography.caption.copyWith(color: s.ink),
                  ),
                ],
              ),
            ],
          ),
          if (derivation != null) ...[
            const SizedBox(height: AppSpacing.md),
            _KeyValue(
              label: 'Derivation',
              child: Text(
                derivation,
                style: AppTypography.mono.copyWith(color: s.ink),
              ),
            ),
          ],
          if (descriptor != null) ...[
            const SizedBox(height: AppSpacing.md),
            // Shown so the user can compare it with their device or keep it
            // as a backup.
            CodeBox(value: descriptor, label: 'Descriptor', maxLines: 3),
          ],
          if (n.action != null && n.actionLabel != null) ...[
            const SizedBox(height: AppSpacing.md),
            SecondaryButton(
              label: n.busy ? 'Working…' : n.actionLabel!,
              icon: Icons.refresh_outlined,
              isLoading: n.busy,
              onPressed: n.busy ? null : n.action,
            ),
          ],
        ],
      ),
    );
  }
}

/// A card: `panel`, a hairline, radius 12.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: child,
    );
  }
}

/// A key in the secondary ink and its value beside it.
class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: AppTypography.label.copyWith(color: s.inkSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: child),
      ],
    );
  }
}

/// 6 px status dot.
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

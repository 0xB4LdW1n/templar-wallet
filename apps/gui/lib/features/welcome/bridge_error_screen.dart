import 'dart:io';

import 'package:flutter/material.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/code_box.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../vault/vault_unlock_screen.dart' show VaultBrandLine;

/// Fatal startup screen: the native wallet engine (wallet-ffi library) could
/// not be loaded. Shown in non-debug builds instead of the app — without the
/// engine there is no real wallet data, and falling back to mock data would
/// show phantom wallets and addresses nobody controls.
///
/// The pre-wallet column, like the vault screens: the mark, a danger glyph
/// and the headline, what happened, the raw error in a well to copy, and the
/// one way out. No accent: nothing here is an action the app wants taken.
class BridgeErrorScreen extends StatelessWidget {
  const BridgeErrorScreen({super.key, required this.error});

  /// The load failure — includes the underlying dlopen error and every
  /// candidate path the loader tried.
  final Object error;

  /// Wider than the vault column: the error lists file paths, and a path
  /// broken over many lines is hard to report.
  static const double _columnWidth = 560;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final p = AppSpacing.pagePadding(context);
    return Scaffold(
      backgroundColor: s.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _columnWidth + 2 * p),
              child: Padding(
                padding: EdgeInsets.all(p),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const VaultBrandLine(),
                    const SizedBox(height: AppSpacing.xxl),
                    Icon(
                      Icons.link_off_outlined,
                      size: AppSpacing.xl,
                      color: s.danger,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'The wallet engine could not be loaded',
                      style: AppTypography.displayTitleOf(
                        context,
                      ).copyWith(color: s.ink),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Templar Wallet could not start its native wallet engine, '
                      'so it cannot show or manage any wallets. Your wallet '
                      'files on disk are untouched.',
                      style: AppTypography.body.copyWith(color: s.inkSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    CodeBox(
                      label: 'Error details',
                      value: '$error',
                      maxLines: 16,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'What you can do',
                      style: AppTypography.eyebrow.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _step(
                      s,
                      1,
                      'Reinstall Templar Wallet — the engine library may be '
                      'missing or damaged.',
                    ),
                    _step(
                      s,
                      2,
                      'If the problem persists, report the issue and include '
                      'the error details above (use the copy button).',
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SecondaryButton(
                        label: 'Quit',
                        icon: Icons.close_outlined,
                        onPressed: () => exit(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _step(AppScheme s, int n, String text) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: AppSpacing.xl,
          child: Text(
            '$n.',
            style: AppTypography.mono.copyWith(color: s.inkFaint),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(color: s.inkSecondary),
          ),
        ),
      ],
    ),
  );
}

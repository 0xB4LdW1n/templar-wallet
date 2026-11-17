import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/seal_mark.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../wallet_picker/entry_controls.dart';

// First run, no wallets yet. The screen says what the product does in its
// own nouns and then shows it: the left column is the headline and the two
// ways in, the right half a still picture of the thing this wallet exists
// for — a transaction collecting signatures under a policy. The picture is
// drawn from the app's own pieces (the seal, the mono fingerprints) so it is
// plainly this product and no other.

const String _headline = 'Bitcoin and Liquid custody under Miniscript policies';
const String _line =
    'One key, several keys, a hardware device or an air-gapped signer. '
    'Test networks only.';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // The entry screens always show the brand accent. Defer past the current
    // build so notifyListeners doesn't fire mid-build.
    final app = context.read<AppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) app.setAccent(null);
    });

    // The first time, the screen enters once (a fade, nothing moves); after
    // that it is simply there.
    _c = AnimationController(vsync: this, duration: AppMotion.emphasized);
    if (app.firstRunSeen) {
      _c.value = 1.0;
    } else {
      _c.forward();
      app.markFirstRunSeen();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context) && _c.isAnimating) {
      _c.stop();
      _c.value = 1.0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _create() => context.go(AppRoutes.walletType);
  void _restore() => context.go(AppRoutes.importWallet);

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return Scaffold(
      backgroundColor: s.canvas,
      body: SafeArea(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _c, curve: AppMotion.settle),
          child: phone
              ? _PhoneLayout(onCreate: _create, onRestore: _restore)
              : _DesktopLayout(onCreate: _create, onRestore: _restore),
        ),
      ),
    );
  }
}

// ── Desktop: an asymmetric split ──────────────────────────────────────────────

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.onCreate, required this.onRestore});

  final VoidCallback onCreate;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final pad = AppSpacing.pagePadding(context);
    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              child: _Scrollable(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.huge,
                    AppSpacing.xxxl,
                    AppSpacing.xxl,
                    AppSpacing.xxxl,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppLogo(size: 40),
                          const SizedBox(height: AppSpacing.xxl),
                          Text(
                            _headline,
                            style: AppTypography.displayTitle.copyWith(
                              color: s.ink,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _line,
                            style: AppTypography.bodyLarge.copyWith(
                              color: s.inkSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          Row(
                            children: [
                              PrimaryButton(
                                label: 'Create wallet',
                                onPressed: onCreate,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              SecondaryButton(
                                label: 'Restore wallet',
                                onPressed: onRestore,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          const _TestnetNote(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _Scrollable(
                child: Padding(
                  padding: EdgeInsets.all(pad),
                  child: const Center(child: _PolicyPreview()),
                ),
              ),
            ),
          ],
        ),
        Positioned(top: pad, right: pad, child: const ThemeToggleButton()),
      ],
    );
  }
}

/// Centres its child vertically while it fits and scrolls once the window is
/// shorter than the content.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

// ── Phone: one column, the actions pinned to the thumb ────────────────────────

class _PhoneLayout extends StatelessWidget {
  const _PhoneLayout({required this.onCreate, required this.onRestore});

  final VoidCallback onCreate;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final pad = AppSpacing.pagePadding(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [AppLogo(size: 40), Spacer(), ThemeToggleButton()],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  _headline,
                  style: AppTypography.displayTitleOf(
                    context,
                  ).copyWith(color: s.ink),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _line,
                  style: AppTypography.bodyOf(
                    context,
                  ).copyWith(color: s.inkSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                const _PolicyPreview(compact: true),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: _TestnetNote()),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Create wallet',
                isFullWidth: true,
                onPressed: onCreate,
              ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: 'Restore wallet',
                isFullWidth: true,
                onPressed: onRestore,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The network, said once and quietly: a 6 px testnet dot and one line.
class _TestnetNote extends StatelessWidget {
  const _TestnetNote();

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: s.testnet,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'Testnet only — no mainnet funds',
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
      ],
    );
  }
}

// ── The picture ───────────────────────────────────────────────────────────────

/// A still picture of a 2-of-3 transaction mid-signing, built from the
/// app's components. Not a control: it is excluded from semantics and
/// stands as one labelled image. This is the one place outside a signing
/// flow where the seal appears, because it depicts one.
///
/// [compact] (phone) keeps the keys and the signature count and drops the
/// transaction line, so the actions stay above the fold.
class _PolicyPreview extends StatelessWidget {
  const _PolicyPreview({this.compact = false});

  final bool compact;

  static const _keys = [
    ('Laptop', 'a3f1c29e', true),
    ('Jade', '5b7d0e44', true),
    ('Air-gapped signer', 'c81f6a02', false),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final rowHeight = AppSpacing.xxxl;
    return Semantics(
      image: true,
      label: 'Preview of a 2-of-3 multisig transaction',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: compact ? double.infinity : 480,
          ),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            decoration: BoxDecoration(
              color: s.panel,
              borderRadius: BorderRadius.circular(
                compact ? AppSpacing.radiusLg : AppSpacing.radiusXl,
              ),
              border: Border.all(color: s.edge),
              boxShadow: s.panelShadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Treasury 2-of-3',
                  style: AppTypography.sectionTitle.copyWith(color: s.ink),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final k in _keys)
                  SizedBox(
                    height: rowHeight,
                    child: Row(
                      children: [
                        SealMark(stamped: k.$3),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            k.$1,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(color: s.ink),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          k.$2,
                          style: AppTypography.mono.copyWith(
                            color: s.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Divider(height: 1, thickness: 1, color: s.edge),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Signatures',
                        style: AppTypography.label.copyWith(color: s.ink),
                      ),
                    ),
                    const SealTally(signed: 2, required: 2, size: 16),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '2 of 3 keys · 2 signatures required',
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
                if (!compact) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: s.well,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: s.edge),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '0.25000000 BTC',
                          style: AppTypography.mono.copyWith(color: s.ink),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Icon(
                          Icons.arrow_forward_outlined,
                          size: AppSpacing.iconSmall,
                          color: s.inkFaint,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'tb1q…7kxp',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.mono.copyWith(
                              color: s.inkSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

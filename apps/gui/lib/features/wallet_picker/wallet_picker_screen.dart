import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/routes.dart';
import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../services/wallet_customization_store.dart';
import '../../shared/relative_time.dart';
import '../../shared/widgets/app_logo.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/wallet_plate.dart';
import '../hardware/ledger_connect_dialog.dart';
import '../vault/lock_action.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'entry_controls.dart';
import 'models/wallet_summary.dart';
import 'wallet_flags.dart';

// "Wallets": the app's entry once at least one wallet exists. A top bar with
// the product mark, a title with the two ways to add a wallet, and the
// wallets as a register (design.md, "The moments"): one card, one row per
// wallet — a spine in the wallet's own colour (the accent the app wears once
// that wallet is open), the glyph of its kind, its name over how its keys
// are held, its chains and its fingerprint in columns that line up.
//
// The screen exists to get back into a wallet, and almost always the same
// one. So the cursor starts on the wallet opened last and Enter opens it;
// the arrows move the cursor, the pointer moves it too, and 1–9 open a row
// outright. The rows keep the order of their kinds, so a digit means the
// same wallet every day.
//
// The block sits in the upper middle of the window rather than stranded at
// its top; a long list scrolls as usual. New wallet is the screen's one
// accent control.

/// Widest the page's column grows before it stops and centres.
const double _columnMax = 960;

/// The keys that open the first nine rows.
const List<LogicalKeyboardKey> _digitKeys = [
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// The order rows are laid in: wallets that sign here first, then the ones
/// that sign elsewhere, then the ones that only watch. The engine's own order
/// is kept inside each kind.
int _kindRank(WalletSummary w) {
  if (w.isAirgapWallet) return 3;
  if (w.isViewOnlyWallet) return 4;
  if (w.type == WalletType.multisig) return 1;
  if (w.isHardwareWallet) return 2;
  if (w.type == WalletType.watchOnly || w.isWatchOnly) return 4;
  return 0;
}

class WalletPickerScreen extends StatefulWidget {
  const WalletPickerScreen({super.key});

  @override
  State<WalletPickerScreen> createState() => _WalletPickerScreenState();
}

class _WalletPickerScreenState extends State<WalletPickerScreen> {
  final _bridge = walletBridge;
  final _searchController = TextEditingController();
  List<WalletSummary> _wallets = [];

  /// What this device keeps about each wallet (name, colour, lock, when it
  /// was last opened), read once with the list so the rows draw whole.
  Map<String, WalletCustomization> _customs = {};
  bool _loading = true;
  String? _error;
  String _query = '';

  /// The row the keyboard is on, as an index into [_filtered]. It starts on
  /// the wallet opened last.
  int _cursor = 0;

  /// Storage is open — the header offers to lock it. Never guessed: no
  /// status, no button.
  bool _vaultUnlocked = false;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshVault();
  }

  Future<void> _refreshVault() async {
    try {
      final v = await _bridge.vaultStatus();
      if (mounted) {
        setState(() => _vaultUnlocked = v.initialized && v.unlocked);
      }
    } catch (_) {
      if (mounted) setState(() => _vaultUnlocked = false);
    }
  }

  Future<void> _lock() async {
    await lockVaultAndPrompt(
      context,
      onUnlocked: () {
        if (mounted) _refreshVault();
      },
    );
    if (mounted) _refreshVault();
  }

  Future<void> _load() async {
    // This is the app's entry screen: a bridge failure here (instance lock
    // held, unreadable registry) must surface its message, not spin forever.
    final List<WalletSummary> wallets;
    try {
      wallets = await _bridge.listWallets();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
      return;
    }
    if (!mounted) return;
    // Entry screen always shows the brand accent, not the last wallet's tint.
    context.read<AppState>().setAccent(null);
    if (wallets.isEmpty) {
      context.go(AppRoutes.welcome);
      return;
    }
    final customs = <String, WalletCustomization>{};
    for (final w in wallets) {
      customs[w.id] = await WalletCustomizationStore.instance.load(w.id);
    }
    if (!mounted) return;
    setState(() {
      _wallets = wallets;
      _customs = customs;
      _loading = false;
      _error = null;
      _cursor = _lastOpenedIndex();
    });
  }

  /// Where the wallet opened most recently sits in [_filtered]; the first
  /// row when none was ever opened from here.
  int _lastOpenedIndex() {
    final shown = _filtered;
    var best = 0;
    var bestAt = 0;
    for (var i = 0; i < shown.length; i++) {
      final at = _customs[shown[i].id]?.lastOpenedAt ?? 0;
      if (at > bestAt) {
        bestAt = at;
        best = i;
      }
    }
    return best;
  }

  void _moveCursor(int by) {
    final n = _filtered.length;
    if (n == 0) return;
    setState(() => _cursor = (_cursor + by).clamp(0, n - 1));
  }

  void _openCursor() {
    final shown = _filtered;
    if (_loading || _error != null || shown.isEmpty) return;
    _openWallet(shown[_cursor.clamp(0, shown.length - 1)]);
  }

  List<WalletSummary> get _filtered {
    final shown = [
      for (final w in _wallets)
        if (w.name.toLowerCase().contains(_query.toLowerCase())) w,
    ];
    // Stable: equal ranks keep the order the engine listed them in.
    final order = {for (var i = 0; i < shown.length; i++) shown[i].id: i};
    shown.sort((a, b) {
      final byKind = _kindRank(a).compareTo(_kindRank(b));
      return byKind != 0 ? byKind : order[a.id]!.compareTo(order[b.id]!);
    });
    return shown;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    // Search only earns its place once the list is long enough that
    // scanning it by eye stops working.
    final showSearch = _wallets.length > 6;
    final numbered = !showSearch && !AppLayout.isPhone(context);
    final phone = AppLayout.isPhone(context);
    final pad = AppSpacing.pagePadding(context);

    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = _LoadError(
        message: _error!,
        onRetry: () {
          setState(() {
            _loading = true;
            _error = null;
          });
          _load();
        },
      );
    } else if (_filtered.isEmpty) {
      body = _NoMatches(query: _query);
    } else {
      body = _WalletRegister(
        wallets: _filtered,
        customs: _customs,
        cursor: _cursor.clamp(0, _filtered.length - 1),
        numbered: numbered,
        onCursor: (i) {
          if (i != _cursor) setState(() => _cursor = i);
        },
        onOpen: _openWallet,
      );
    }

    // The arrows move the cursor and Enter opens the row it is on. 1–9 open
    // the row that carries the number — only while there is no search field
    // on the page: a digit typed there is part of a name.
    final shown = _filtered;
    final ready = !_loading && _error == null && shown.isNotEmpty;
    final shortcuts = <ShortcutActivator, VoidCallback>{
      if (ready && !phone) ...{
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveCursor(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveCursor(-1),
        const SingleActivator(LogicalKeyboardKey.enter): _openCursor,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _openCursor,
      },
      if (numbered && ready)
        for (var i = 0; i < shown.length && i < _digitKeys.length; i++)
          SingleActivator(_digitKeys[i]): () => _openWallet(shown[i]),
    };

    return Scaffold(
      backgroundColor: s.canvas,
      body: SafeArea(
        child: CallbackShortcuts(
          bindings: shortcuts,
          child: Focus(
            autofocus: true,
            child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: _columnMax,
                      minHeight: viewport.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        pad,
                        phone ? AppSpacing.sm : AppSpacing.xl,
                        pad,
                        phone ? AppSpacing.lg : AppSpacing.xl,
                      ),
                      // Intrinsic height lets the two spacers share whatever
                      // the window has left: the block rides in the upper
                      // middle on a tall window and the page simply scrolls
                      // once the rows outgrow it.
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _TopBar(
                              // Desktop only: on a phone the lock lives in
                              // Settings, next to the same switch that opens
                              // it.
                              onLock: _vaultUnlocked && !phone ? _lock : null,
                            ),
                            if (phone)
                              const SizedBox(height: AppSpacing.xl)
                            else ...[
                              const SizedBox(height: AppSpacing.xxl),
                              const Spacer(flex: 2),
                            ],
                            _Header(count: _loading ? null : _wallets.length),
                            if (showSearch) ...[
                              const SizedBox(height: AppSpacing.xl),
                              TextField(
                                controller: _searchController,
                                decoration: const InputDecoration(
                                  hintText: 'Search',
                                  prefixIcon: Icon(
                                    Icons.search_outlined,
                                    size: AppSpacing.icon,
                                  ),
                                ),
                                onChanged: (v) => setState(() {
                                  _query = v;
                                  _cursor = 0;
                                }),
                                onSubmitted: (_) => _openCursor(),
                              ),
                            ],
                            SizedBox(
                              height: phone ? AppSpacing.lg : AppSpacing.xxl,
                            ),
                            body,
                            if (phone)
                              const SizedBox(height: AppSpacing.xl)
                            else ...[
                              const SizedBox(height: AppSpacing.xxl),
                              const Spacer(flex: 5),
                            ],
                            _Footer(keys: ready && !phone, digits: numbered),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openWallet(WalletSummary wallet) async {
    // Read again rather than trust the list: the password gate must be the
    // one on disk now.
    final custom = await WalletCustomizationStore.instance.load(wallet.id);
    if (!mounted) return;

    if (custom.passwordHash != null) {
      final ok = await _showPasswordPrompt(custom.passwordHash!);
      if (!ok || !mounted) return;
    }

    final displayName = custom.nameOverride ?? wallet.name;

    // Apply the wallet's personal accent across the whole app.
    if (mounted) {
      context.read<AppState>().setAccent(
        custom.accentColor != null ? Color(custom.accentColor!) : null,
      );
    }

    // For USB hardware wallets, ask intent first: connect the device now, or
    // open watch-only (balance + receive only). "Connect" runs the scan wizard.
    var hwWatchOnly = false;
    if (wallet.isHardwareWallet) {
      final choice = await showHwOpenChoiceDialog(
        context,
        walletName: displayName,
      );
      if (!mounted) return;
      switch (choice) {
        case HwOpenChoice.cancelled:
          return;
        case HwOpenChoice.watchOnly:
          hwWatchOnly = true;
        case HwOpenChoice.connect:
          final result = await showLedgerConnectDialog(
            context,
            expectedFingerprint: fingerprintFromTypeLabel(wallet.typeLabel),
          );
          if (!mounted) return;
          switch (result) {
            case LedgerConnectResult.cancelled:
              return;
            case LedgerConnectResult.watchOnly:
              hwWatchOnly = true;
            case LedgerConnectResult.connected:
              hwWatchOnly = false;
          }
      }
    }
    context.read<AppState>().setActiveWallet(
      wallet.id,
      name: displayName,
      type: wallet.displayType,
      hwWatchOnly: hwWatchOnly,
      liquid: wallet.liquidEnabled,
      bitcoin: wallet.bitcoinEnabled,
    );
    // The wallet shell this picker replaced leaves the tree only when the
    // picker's own page transition ends. Re-entering the shell before then
    // (a quick tap right after a wallet was closed — by a network switch,
    // a test-server join or leave, a lock) puts two shells in the tree at
    // once, and go_router keys each shell's navigator with the same
    // GlobalObjectKey: "Multiple widgets used the same GlobalKey". So a tap
    // that lands mid-transition waits for it to end.
    await _untilRouteSettled();
    if (mounted) context.go(AppRoutes.dashboard);
  }

  Future<void> _untilRouteSettled() async {
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) return;
    final settled = Completer<void>();
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed && !settled.isCompleted) {
        settled.complete();
      }
    }

    animation.addStatusListener(onStatus);
    // A transition lasts a few hundred ms; never hang the tap on one that
    // does not report its end.
    await settled.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    animation.removeStatusListener(onStatus);
  }

  Future<bool> _showPasswordPrompt(String storedHash) async {
    return await showAppDialog<bool>(
          context,
          barrierDismissible: false,
          builder: (_) => _WalletPasswordDialog(storedHash: storedHash),
        ) ??
        false;
  }
}

// ── Top bar and header ────────────────────────────────────────────────────────

/// The product mark and its name, and the two controls that exist before a
/// wallet is open: the storage lock (when storage is open) and the theme.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onLock});

  final VoidCallback? onLock;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final lock = onLock;
    return Row(
      children: [
        AppLogo(size: phone ? 32 : 44),
        SizedBox(width: phone ? AppSpacing.sm : AppSpacing.md),
        Expanded(
          child: Text(
            'Templar Wallet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (phone ? AppTypography.sectionTitle : AppTypography.brand)
                .copyWith(color: s.ink),
          ),
        ),
        if (lock != null) ...[
          EntryIconButton(
            icon: Icons.lock_outline,
            tooltip: 'Lock wallet storage',
            onPressed: lock,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        const ThemeToggleButton(),
      ],
    );
  }
}

/// "Wallets", how many there are, and the two ways to add one — a pair of
/// equal buttons. On a phone they go under the title as two halves.
class _Header extends StatelessWidget {
  const _Header({required this.count});

  /// Null while the list is loading: no number is printed before it is known.
  final int? count;

  /// One width for the pair, so Restore and New wallet are the same size.
  static const double _pairWidth = 176;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final n = count;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Wallets',
          style: AppTypography.entryTitleOf(context).copyWith(color: s.ink),
        ),
        if (n != null && n > 0) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            n == 1 ? '1 wallet on this device' : '$n wallets on this device',
            style: AppTypography.bodyOf(
              context,
            ).copyWith(color: s.inkSecondary),
          ),
        ],
      ],
    );
    final restore = SecondaryButton(
      label: 'Restore',
      icon: Icons.settings_backup_restore_outlined,
      isFullWidth: true,
      large: true,
      onPressed: () => context.go(AppRoutes.importWallet),
    );
    final create = PrimaryButton(
      label: 'New wallet',
      icon: Icons.add,
      isFullWidth: true,
      large: true,
      onPressed: () => context.go(AppRoutes.walletType),
    );
    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: restore),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: create),
            ],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: title),
        SizedBox(width: _pairWidth, child: restore),
        const SizedBox(width: AppSpacing.md),
        SizedBox(width: _pairWidth, child: create),
      ],
    );
  }
}

/// The foot of the entry screen: the one fact that is true of every wallet
/// here — the dot is the testnet marker the Dashboard carries — and, where
/// there is a keyboard, the keys the register answers to.
class _Footer extends StatelessWidget {
  const _Footer({required this.keys, required this.digits});

  /// The register is up and this is not a phone: print the keys.
  final bool keys;

  /// The rows are numbered (no search field is taking the digits).
  final bool digits;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final quiet = AppTypography.caption.copyWith(color: s.inkFaint);
    Widget hint(List<Widget> caps, String what) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in caps) ...[c, const SizedBox(width: AppSpacing.xs)],
        const SizedBox(width: AppSpacing.xs),
        Text(what, style: quiet),
      ],
    );
    return Row(
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
        Expanded(child: Text('Test networks only', style: quiet)),
        if (keys) ...[
          hint(const [
            _Keycap.icon(Icons.arrow_upward_outlined),
            _Keycap.icon(Icons.arrow_downward_outlined),
          ], 'choose'),
          const SizedBox(width: AppSpacing.xl),
          hint(const [_Keycap.icon(Icons.keyboard_return_outlined)], 'open'),
          if (digits) ...[
            const SizedBox(width: AppSpacing.xl),
            hint(const [_Keycap('1–9')], 'open by number'),
          ],
        ],
      ],
    );
  }
}

// ── Load failure ──────────────────────────────────────────────────────────────
// Startup errors ("Another Templar Wallet instance is already running…",
// "Wallet storage could not be read: …") are actionable sentences — show them
// in full so the user knows what to fix before retrying.

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: s.panel,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: s.edge),
            boxShadow: s.panelShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: AppSpacing.icon,
                    color: s.danger,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Could not load your wallets',
                      style: AppTypography.sectionTitle.copyWith(color: s.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: AppTypography.body.copyWith(color: s.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: PrimaryButton(
                  label: 'Retry',
                  isFullWidth: AppLayout.isPhone(context),
                  onPressed: onRetry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── The register ──────────────────────────────────────────────────────────────

/// A row's height on desktop: a 48 px mark and two lines, with air.
const double _rowHeight = 84;

/// The spine: the wallet's own colour down the row's leading edge.
const double _spine = 4;

/// Where a row's text starts, past the spine, the inset and the mark — the
/// hairlines between rows start here too.
const double _rowTextInset =
    _spine + AppSpacing.cardPadding + AppSpacing.xxxl + AppSpacing.lg;

/// The wallets as one register: a card of rows, each a wallet, with the
/// cursor on the one opened last (design.md, "The moments").
class _WalletRegister extends StatelessWidget {
  const _WalletRegister({
    required this.wallets,
    required this.customs,
    required this.cursor,
    required this.numbered,
    required this.onCursor,
    required this.onOpen,
  });

  final List<WalletSummary> wallets;

  /// What this device knows about each wallet: its name override, its
  /// colour, its lock, when it was last opened.
  final Map<String, WalletCustomization> customs;

  /// The row the keyboard is on; Enter opens it.
  final int cursor;

  /// The first nine rows carry the digit that opens them.
  final bool numbered;

  /// The pointer moved onto a row: the cursor follows it.
  final ValueChanged<int> onCursor;
  final void Function(WalletSummary) onOpen;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    // The wallet opened most recently, if any was: it says so.
    String? lastId;
    var lastAt = 0;
    for (final w in wallets) {
      final at = customs[w.id]?.lastOpenedAt ?? 0;
      if (at > lastAt) {
        lastAt = at;
        lastId = w.id;
      }
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < wallets.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: s.edge,
                indent: phone
                    ? _spine + AppSpacing.md + 44 + AppSpacing.md
                    : _rowTextInset,
              ),
            _WalletRow(
              key: ValueKey(wallets[i].id),
              wallet: wallets[i],
              custom: customs[wallets[i].id],
              current: !phone && i == cursor,
              lastOpened: wallets[i].id == lastId,
              shortcut: numbered && i < _digitKeys.length ? i + 1 : null,
              onHover: () => onCursor(i),
              onTap: () => onOpen(wallets[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Text(
      'No wallet matches “$query”',
      style: AppTypography.body.copyWith(color: s.inkSecondary),
    );
  }
}

/// A chain the wallet carries: its hue as a 6 px dot, then its name.
class _ChainMark extends StatelessWidget {
  const _ChainMark({required this.color, required this.label});

  final Color color;
  final String label;

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
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
      ],
    );
  }
}

/// A key as it is printed on the keyboard: a 24 px cap with a hairline,
/// holding the key's legend or — for Enter and the arrows, which no text
/// face is sure to carry — its glyph.
class _Keycap extends StatelessWidget {
  const _Keycap(String this.label) : icon = null, strong = false;
  const _Keycap.icon(IconData this.icon, {this.strong = false}) : label = null;

  final String? label;
  final IconData? icon;

  /// The key that acts on the row under the cursor.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final ink = strong ? s.ink : s.inkSecondary;
    return Container(
      constraints: const BoxConstraints(minWidth: AppSpacing.xl),
      height: AppSpacing.xl,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: strong ? s.panel : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        border: Border.all(color: s.edgeStrong),
      ),
      child: icon != null
          ? Icon(icon, size: AppSpacing.md, color: ink)
          : Text(label!, style: AppTypography.monoSmall.copyWith(color: ink)),
    );
  }
}

/// One wallet as a row of the register: a spine in the wallet's own colour,
/// the glyph of its kind, its name over how its keys are held, the chains
/// it carries, its fingerprint, and the key that opens it.
///
/// The row under the cursor is the raised surface and shows the Enter key;
/// the pointer moves the cursor, so there is one such row at a time and
/// Enter always opens what is lit.
class _WalletRow extends StatefulWidget {
  const _WalletRow({
    super.key,
    required this.wallet,
    required this.custom,
    required this.current,
    required this.lastOpened,
    required this.onHover,
    required this.onTap,
    this.shortcut,
  });

  final WalletSummary wallet;
  final WalletCustomization? custom;

  /// The cursor is on this row.
  final bool current;

  /// The wallet opened most recently on this device.
  final bool lastOpened;

  /// The digit that opens this row from the keyboard, printed as a keycap.
  final int? shortcut;

  final VoidCallback onHover;
  final VoidCallback onTap;

  @override
  State<_WalletRow> createState() => _WalletRowState();
}

class _WalletRowState extends State<_WalletRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final w = widget.wallet;
    final custom = widget.custom;
    final name = custom?.nameOverride ?? w.name;
    // The colour the wallet was given in Settings, or the brand's: either
    // way it is the accent the app wears once this wallet is open.
    final colour = custom?.accentColor != null
        ? Color(custom!.accentColor!)
        : AppColors.accentDefault;
    final locked = custom?.passwordHash != null;
    final fp = w.masterFingerprint;
    final hasFp = fp != null && fp.isNotEmpty;
    final lit = widget.current || _down;
    final opened = custom?.lastOpenedAt;

    final title = Row(
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.galleryTitleOf(context).copyWith(color: s.ink),
          ),
        ),
        if (locked) ...[
          const SizedBox(width: AppSpacing.sm),
          Tooltip(
            message: 'Password protected',
            child: Icon(
              Icons.lock_outline,
              size: AppSpacing.iconSmall,
              color: s.inkFaint,
            ),
          ),
        ],
      ],
    );
    // How the keys are held, then when it was last opened: the two facts
    // that tell this wallet from the one beside it.
    final facts = Text(
      [
        WalletFlags.kindLabel(w),
        if (opened != null)
          '${widget.lastOpened ? 'Last opened' : 'Opened'} '
              '${relativeTimeShort(DateTime.fromMillisecondsSinceEpoch(opened))}',
      ].join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.caption.copyWith(color: s.inkSecondary),
    );
    final chains = Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        if (w.bitcoinEnabled) _ChainMark(color: s.bitcoin, label: 'Bitcoin'),
        if (w.liquidEnabled) _ChainMark(color: s.liquid, label: 'Liquid'),
      ],
    );
    final fingerprint = Text(
      hasFp ? fp : '',
      maxLines: 1,
      style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
    );
    final arrow = Icon(
      Icons.arrow_forward_outlined,
      size: AppSpacing.navIcon,
      color: lit ? s.ink : s.inkFaint,
    );

    final Widget content;
    if (phone) {
      // Phone: the same facts on three lines, the whole row one target.
      content = Row(
        children: [
          WalletPlate(icon: WalletFlags.kindIcon(w), size: 44),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                facts,
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: chains),
                    if (hasFp) fingerprint,
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          arrow,
        ],
      );
    } else {
      final shortcut = widget.shortcut;
      content = Row(
        children: [
          WalletPlate(
            icon: WalletFlags.kindIcon(w),
            size: AppSpacing.xxxl,
            raised: lit,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, facts],
            ),
          ),
          const SizedBox(width: AppSpacing.xl),
          // Fixed columns: the chains and the fingerprints of every row
          // line up, so two wallets are compared down a column.
          SizedBox(width: 168, child: chains),
          SizedBox(
            width: 88,
            child: Align(alignment: Alignment.centerRight, child: fingerprint),
          ),
          const SizedBox(width: AppSpacing.xl),
          SizedBox(
            width: AppSpacing.xxl,
            child: Center(
              child: widget.current
                  ? const Tooltip(
                      message: 'Press Enter to open',
                      child: _Keycap.icon(
                        Icons.keyboard_return_outlined,
                        strong: true,
                      ),
                    )
                  : shortcut == null
                  ? null
                  : Tooltip(
                      message: 'Press $shortcut to open',
                      child: _Keycap('$shortcut'),
                    ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          arrow,
        ],
      );
    }

    final row = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      constraints: BoxConstraints(minHeight: phone ? 0 : _rowHeight),
      color: _down
          ? Color.alphaBlend(s.pressed, s.selected)
          : widget.current
          ? s.selected
          : s.selected.withValues(alpha: 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: _spine,
              child: ColoredBox(color: colour),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: phone ? AppSpacing.md : AppSpacing.cardPadding,
                  vertical: phone ? AppSpacing.lg : AppSpacing.md,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      selected: widget.current,
      label: [
        name,
        WalletFlags.describe(w),
        if (widget.lastOpened) 'last opened',
      ].join(', '),
      excludeSemantics: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => widget.onHover(),
        onHover: (_) {
          if (!widget.current) widget.onHover();
        },
        onExit: (_) {
          if (_down) setState(() => _down = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: row,
        ),
      ),
    );
  }
}

class _WalletPasswordDialog extends StatefulWidget {
  const _WalletPasswordDialog({required this.storedHash});
  final String storedHash;

  @override
  State<_WalletPasswordDialog> createState() => _WalletPasswordDialogState();
}

class _WalletPasswordDialogState extends State<_WalletPasswordDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (WalletCustomizationStore.verifyPassword(
      _ctrl.text,
      widget.storedHash,
    )) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = 'Incorrect password');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return PromptDialog(
      title: 'Wallet locked',
      icon: Icons.lock_outline,
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PrimaryButton(label: 'Unlock', onPressed: _submit),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter the password to open this wallet',
            style: AppTypography.body.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          PasswordField(
            controller: _ctrl,
            autofocus: true,
            errorText: _error,
            onSubmitted: _submit,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        ],
      ),
    );
  }
}

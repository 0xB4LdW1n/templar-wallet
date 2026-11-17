import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'app_state.dart';
import 'back_handler.dart';
import 'routes.dart';
import '../bridge/bridge_provider.dart';
import '../dev/shot_mode.dart';
import '../bridge/wallet_bridge.dart';
import '../services/wallet_customization_store.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_scheme.dart';
import '../shared/widgets/app_logo.dart';
import '../shared/widgets/hybrid_kit.dart' show CurrentMark;
import '../shared/widgets/mobile_tab_bar.dart';
import '../shared/widgets/segmented_switch.dart';
import '../shared/widgets/wallet_plate.dart';
import '../features/wallet_picker/wallet_flags.dart';
import '../features/vault/lock_action.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

// ── Shell ─────────────────────────────────────────────────────────────────────

/// The frame around every in-wallet page: the sidebar on a desktop, the
/// header and tab bar on a phone (design.md, "Navigation").
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child, required this.currentPath});
  final Widget child;
  final String currentPath;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool _expanded = true;

  /// The wallet this shell last stamped as opened.
  String? _stamped;

  void _toggle() => setState(() => _expanded = !_expanded);

  /// Being inside a wallet's shell is what "opened" means, however it was
  /// reached — picked from the list, just created, restored, or chosen by a
  /// protocol link. The wallet list starts on the one stamped last. Local
  /// display metadata, best effort: a failed write changes nothing else.
  void _stampOpened(String? walletId) {
    if (walletId == null || walletId == _stamped) return;
    _stamped = walletId;
    WalletCustomizationStore.instance.markOpened(walletId).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    _stampOpened(context.select<AppState, String?>((st) => st.activeWalletId));
    // Phones and tablets get the header + tab bar shell.
    if (AppLayout.isMobilePlatform) {
      return MobileShell(currentPath: widget.currentPath, child: widget.child);
    }

    final s = AppScheme.of(context);
    final width = _expanded
        ? AppSpacing.sidebarWidth
        : AppSpacing.sidebarWidthCollapsed;

    return Scaffold(
      backgroundColor: s.canvas,
      body: Row(
        children: [
          // The width changes in one step: animating it would re-lay out the
          // whole page on every frame of the move.
          RepaintBoundary(
            child: Container(
              width: width,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: s.chrome,
                border: Border(right: BorderSide(color: s.edge)),
              ),
              child: _Sidebar(
                currentPath: widget.currentPath,
                expanded: _expanded,
                onToggle: _toggle,
              ),
            ),
          ),
          Expanded(
            child: RepaintBoundary(child: _BadgedContent(child: widget.child)),
          ),
        ],
      ),
    );
  }
}

// ── Page content ──────────────────────────────────────────────────────────────

/// The routed page, with the mock-data and regtest strips stacked above it
/// whenever they apply. Shared by the desktop and mobile shells.
class _BadgedContent extends StatelessWidget {
  const _BadgedContent({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, bool>(
      selector: (_, s) => s.isLiquidRegtest,
      builder: (context, isRegtest, child) {
        // kShotMode: documentation screenshots run on the mock bridge on
        // purpose, and the strip would be in every picture (see
        // lib/dev/shot_mode.dart). Never false in a shipped build.
        final showMock = isMockBridge && !kShotMode;
        if (!showMock && !isRegtest) return child!;
        return Column(
          children: [
            if (showMock) const _MockDataBadge(),
            if (isRegtest) const _RegtestBadge(),
            Expanded(child: child!),
          ],
        );
      },
      child: child,
    );
  }
}

// ── Mobile shell ──────────────────────────────────────────────────────────────

/// The phone shell: a thin header (wallet, sync), the page, and the tab
/// bar in place of the sidebar. Lock and theme live in Settings here.
///
/// Also owns the Android back button for everything inside the shell. A
/// screen may claim it through [BackHandler] (the Send wizard steps back);
/// otherwise back leaves a sub-page for its parent ([mobileParentRouteFor]),
/// leaves a tab for the Dashboard, and leaves the app from the
/// Dashboard. The `PopScope` sits on the shell route itself — the page the
/// root navigator shows — because every in-shell navigation is a `go`, so
/// the nested navigator never has anything to pop and go_router hands the
/// press to the root navigator's top route.
class MobileShell extends StatefulWidget {
  const MobileShell({
    super.key,
    required this.child,
    required this.currentPath,
  });
  final Widget child;
  final String currentPath;

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  /// The page's outermost vertical scrollable, as last reported by its
  /// notifications, so a tap on the current tab can bring it back to
  /// the top. Forgotten when the page changes.
  BuildContext? _scrollContext;

  bool get _onDashboard => widget.currentPath == AppRoutes.dashboard;

  @override
  void didUpdateWidget(MobileShell old) {
    super.didUpdateWidget(old);
    if (old.currentPath != widget.currentPath) _scrollContext = null;
  }

  bool _onScrollNotification(Notification n) {
    if (n is ScrollNotification) {
      if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
        _scrollContext = n.context;
      }
    } else if (n is ScrollMetricsNotification) {
      if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
        _scrollContext = n.context;
      }
    }
    return false;
  }

  void _scrollToTop() {
    final ctx = _scrollContext;
    if (ctx == null || !ctx.mounted) return;
    final position = ctx.findAncestorStateOfType<ScrollableState>()?.position;
    if (position == null || !position.hasPixels) return;
    final top = position.minScrollExtent;
    if (position.pixels <= top) return;
    if (AppMotion.reduced(context)) {
      position.jumpTo(top);
    } else {
      position.animateTo(
        top,
        duration: AppMotion.emphasized,
        curve: AppMotion.settle,
      );
    }
  }

  /// One step up: a screen with its own notion of back (the Send wizard)
  /// goes first, then the sub-page's parent, then the Dashboard. Shared by
  /// the system back and the header's arrow so the two never disagree.
  void _goBack() {
    if (BackHandler.instance.dispatch()) return;
    if (_onDashboard) return;
    context.go(mobileParentRouteFor(widget.currentPath) ?? AppRoutes.dashboard);
  }

  void _onPop(bool didPop, Object? result) {
    if (didPop) return;
    _goBack();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final dark = s.isDark;
    final optionalLiquidTools = context.select<AppState, (bool, bool)>(
      (st) => (st.liquidDexEnabled, st.pegEnabled),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Transparent bars, icons following the theme — edge-to-edge itself
      // is switched on in main.dart.
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
      ),
      child: ListenableBuilder(
        listenable: BackHandler.instance,
        builder: (context, child) => PopScope(
          canPop: _onDashboard && !BackHandler.instance.hasHandlers,
          onPopInvokedWithResult: _onPop,
          child: child!,
        ),
        child: Scaffold(
          backgroundColor: s.canvas,
          body: Column(
            children: [
              _MobileHeader(currentPath: widget.currentPath, onBack: _goBack),
              // The Liquid hub: Assets, LiquiDEX and Peg share one tab and
              // are told apart by this strip.
              if (isLiquidHubRoute(widget.currentPath) &&
                  (optionalLiquidTools.$1 || optionalLiquidTools.$2))
                _LiquidHubTabs(currentPath: widget.currentPath),
              Expanded(
                // The header took the status-bar inset; the page must not
                // take it again. The bottom inset is already removed by the
                // Scaffold for a body above a bottomNavigationBar.
                child: Builder(
                  builder: (context) => MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: NotificationListener<Notification>(
                      onNotification: _onScrollNotification,
                      child: RepaintBoundary(
                        child: _BadgedContent(child: widget.child),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // In the Scaffold's own slot rather than at the foot of the
          // Column: the keyboard then covers the bar and the page above it
          // resizes, instead of the bar riding up on top of the keyboard.
          bottomNavigationBar: Selector<AppState, (bool, bool)>(
            selector: (_, st) => (st.activeWalletLiquid, st.loansEnabled),
            builder: (context, flags, _) {
              final (liquid, loans) = flags;
              return MobileTabBar(
                items: mobileNavItems(liquid: liquid, loans: loans),
                currentRoute: mobileNavRouteFor(widget.currentPath),
                onSelect: (route) => context.go(route),
                onReselect: _scrollToTop,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The tabs: the places a wallet is *browsed* from, plus Loans when asked
/// for — six at most, every one visible and labelled. Send and Receive live
/// on the Dashboard (where the balance they act on is), Wallet info sits
/// inside Settings, and LiquiDEX and Peg share the Liquid tab as a switch
/// under the header. The Liquid tab is gated — a Bitcoin-only wallet has
/// nothing to put behind it; Loans is opt-in (`AppState.loansEnabled`) and
/// Liquid-only.
List<MobileTabItem> mobileNavItems({required bool liquid, bool loans = false}) {
  return [
    const MobileTabItem(
      id: 'dashboard',
      label: 'Dashboard',
      route: AppRoutes.dashboard,
      icon: Icons.home_outlined,
    ),
    if (liquid && loans)
      const MobileTabItem(
        id: 'loans',
        label: 'Loans',
        route: AppRoutes.loans,
        icon: Icons.handshake_outlined,
      ),
    const MobileTabItem(
      id: 'history',
      label: 'Activity',
      route: AppRoutes.history,
      icon: Icons.history_outlined,
    ),
    const MobileTabItem(
      id: 'utxos',
      label: 'Coins',
      route: AppRoutes.utxos,
      icon: Icons.account_balance_wallet_outlined,
    ),
    if (liquid)
      const MobileTabItem(
        id: 'liquid',
        label: 'Liquid',
        route: AppRoutes.liquid,
        icon: Icons.water_drop_outlined,
      ),
    const MobileTabItem(
      id: 'settings',
      label: 'Settings',
      route: AppRoutes.settings,
      icon: Icons.settings_outlined,
    ),
  ];
}

// ── Mobile route map ──────────────────────────────────────────────────────────
//
// Every in-shell route is either a tab or a sub-page of one. The three
// functions below are the whole map: which tab a path keeps selected,
// where its back arrow goes, and what the header calls it.

/// Liquid assets, LiquiDEX and Peg: one tab, a switch under the header.
bool isLiquidHubRoute(String path) =>
    path == AppRoutes.liquid || path == AppRoutes.swap || path == AppRoutes.peg;

bool _isLiquidSubScreen(String path) =>
    path == AppRoutes.issueAsset ||
    path == AppRoutes.reissueAsset ||
    path == AppRoutes.burnAsset ||
    path == AppRoutes.assetOperations;

bool _isSettingsSection(String path) =>
    path != AppRoutes.settings && path.startsWith('${AppRoutes.settings}/');

/// The tab a path belongs to. A sub-page keeps its parent's tab selected, so
/// the bar always says where the user came from.
String mobileNavRouteFor(String path) {
  if (path == AppRoutes.loanDetail) return AppRoutes.loans;
  if (path == AppRoutes.send ||
      path == AppRoutes.receive ||
      path == AppRoutes.receiveAddresses) {
    return AppRoutes.dashboard;
  }
  if (isLiquidHubRoute(path) || _isLiquidSubScreen(path)) {
    return AppRoutes.liquid;
  }
  if (path == AppRoutes.walletInfo || _isSettingsSection(path)) {
    return AppRoutes.settings;
  }
  return path;
}

/// Where the header's arrow and the system back lead from [path]; null on a
/// tab, where back means "to the Dashboard" (the shell's default).
String? mobileParentRouteFor(String path) {
  if (path == AppRoutes.loanDetail) return AppRoutes.loans;
  if (path == AppRoutes.send || path == AppRoutes.receive) {
    return AppRoutes.dashboard;
  }
  if (path == AppRoutes.receiveAddresses) return AppRoutes.receive;
  if (_isLiquidSubScreen(path)) return AppRoutes.liquid;
  if (path == AppRoutes.walletInfo || _isSettingsSection(path)) {
    return AppRoutes.settings;
  }
  return null;
}

/// The header title of a sub-page; null on a tab, where the
/// header shows the wallet instead.
String? mobileSubPageTitle(String path) => switch (path) {
  AppRoutes.loanDetail => 'Loan detail',
  AppRoutes.send => 'Send',
  AppRoutes.receive => 'Receive',
  AppRoutes.receiveAddresses => 'All addresses',
  AppRoutes.walletInfo => 'Wallet info',
  AppRoutes.settingsNetwork => 'Nodes and explorers',
  AppRoutes.settingsProtocol => 'Templar Protocol',
  AppRoutes.settingsSecurity => 'Vault and backup',
  AppRoutes.settingsAppearance => 'Theme and units',
  AppRoutes.settingsAdvanced => 'Advanced',
  AppRoutes.settingsAbout => 'About',
  AppRoutes.issueAsset => 'Issue asset',
  AppRoutes.reissueAsset => 'Reissue',
  AppRoutes.burnAsset => 'Burn',
  AppRoutes.assetOperations => 'Asset operations',
  _ => null,
};

// ── Liquid hub tabs ───────────────────────────────────────────────────────────

/// Liquid assets · LiquiDEX · Peg under the header. Each segment is a route, so the
/// strip is only a switch: the three screens are untouched and the tab bar
/// keeps Liquid selected through all of them. Peg needs a Bitcoin side to
/// peg out to; on a Liquid-only wallet the segment stays in place, dimmed,
/// and says why when tapped.
class _LiquidHubTabs extends StatelessWidget {
  const _LiquidHubTabs({required this.currentPath});
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final flags = context.select<AppState, (bool, bool, bool)>(
      (st) => (st.activeWalletBitcoin, st.liquidDexEnabled, st.pegEnabled),
    );
    final (bitcoin, liquidDex, peg) = flags;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.chrome,
        border: Border(bottom: BorderSide(color: s.edge)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        child: SegmentedSwitch<String>(
          dense: true,
          expand: true,
          selected: currentPath,
          onChanged: (route) {
            if (route != currentPath) context.go(route);
          },
          options: [
            const SegOption(value: AppRoutes.liquid, label: 'Liquid assets'),
            if (liquidDex)
              const SegOption(value: AppRoutes.swap, label: 'LiquiDEX'),
            if (peg)
              SegOption(
                value: AppRoutes.peg,
                label: 'Peg',
                enabled: bitcoin,
                tooltip: bitcoin
                    ? null
                    : 'Peg needs a Bitcoin side — this wallet is Liquid-only',
              ),
          ],
        ),
      ),
    );
  }
}

// ── Mobile header ─────────────────────────────────────────────────────────────

/// Largest text scale the header honours: past it the two-line wallet
/// block would push the strip well beyond its 48-dp row.
const double _headerMaxTextScale = 1.3;

/// Height of the header's content row under the status bar: one 48-dp
/// touch row plus 2 dp above and below, ~52 dp in all.
const double _headerRowHeight = AppLayout.minTouchTarget;
const double _headerVerticalPad = 2;

/// Wallet plate, name and kind on the left (tap: the wallet list), the sync
/// state on the right. Sits under the status bar by its own SafeArea and is
/// the only thing that takes that inset — the page below strips it again.
///
/// On a sub-page (Send, Receive, a Settings section, Wallet info) the left
/// half is a back arrow and the page's name instead: the tab bar below still
/// shows the parent, so the wallet is one tap away and the header can spend
/// its width on where the user is and how to leave.
///
/// Kept to one 48-dp row (~52 dp with its pads) so that, with the tab bar,
/// chrome stays well under a fifth of a phone screen. Both controls fill the
/// row, so the whole strip is tappable.
class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.currentPath, required this.onBack});

  final String currentPath;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final subTitle = mobileSubPageTitle(currentPath);
    return Selector<AppState, (String?, String?, String?, bool, bool)>(
      selector: (_, st) => (
        st.activeWalletId,
        st.activeWalletName,
        st.activeWalletType,
        st.activeWalletBitcoin,
        st.activeWalletLiquid,
      ),
      builder: (context, wallet, _) {
        final (walletId, walletName, walletType, bitcoin, liquid) = wallet;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: s.chrome,
            border: Border(bottom: BorderSide(color: s.edge)),
          ),
          child: SafeArea(
            bottom: false,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: _headerMaxTextScale,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  _headerVerticalPad,
                  AppSpacing.lg,
                  _headerVerticalPad,
                ),
                // The row is given its height here: as a plain Column child
                // it has no bounded height of its own, and a stretched Row
                // with unbounded height cannot lay out at all. Both halves
                // then fill the 48 dp, so the whole strip is tappable.
                child: SizedBox(
                  height: _headerRowHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: subTitle != null
                            ? _BackButton(title: subTitle, onTap: onBack)
                            : _WalletButton(
                                walletId: walletId,
                                walletName: walletName,
                                subtitle: _walletSubtitle(
                                  walletType,
                                  bitcoin: bitcoin,
                                  liquid: liquid,
                                ),
                                kindIcon: WalletFlags.kindIconForLabel(
                                  walletType,
                                ),
                              ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      const _SyncPill(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// "Singlesig · Bitcoin + Liquid" — what kind of wallet this is and what it
/// holds, on the one line under its name. Null before a wallet is open.
String? _walletSubtitle(
  String? type, {
  required bool bitcoin,
  required bool liquid,
}) {
  final chains = bitcoin && liquid
      ? 'Bitcoin + Liquid'
      : liquid
      ? 'Liquid'
      : bitcoin
      ? 'Bitcoin'
      : null;
  final parts = <String>[?type, ?chains];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The header's left half: plate, wallet name and kind, one 48-dp target
/// that opens the wallet list.
class _WalletButton extends StatelessWidget {
  const _WalletButton({
    required this.walletId,
    required this.walletName,
    required this.subtitle,
    required this.kindIcon,
  });

  final String? walletId;
  final String? walletName;
  final String? subtitle;
  final IconData kindIcon;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final type = subtitle;
    return Semantics(
      button: true,
      hint: 'Opens the wallet list',
      child: InkWell(
        onTap: () => context.go(AppRoutes.walletPicker),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _headerRowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                WalletPlate(
                  icon: walletId != null
                      ? kindIcon
                      : Icons.account_balance_wallet_outlined,
                  tint: walletId != null ? s.accent : null,
                  size: 32,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              walletId != null
                                  ? (walletName ?? '…')
                                  : 'Open wallet…',
                              style: AppTypography.sectionTitle.copyWith(
                                height: 1.2,
                                color: s.ink,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Icon(
                            Icons.unfold_more_outlined,
                            size: AppSpacing.iconSmall,
                            color: s.inkFaint,
                          ),
                        ],
                      ),
                      if (type != null)
                        Text(
                          type,
                          style: AppTypography.eyebrow.copyWith(
                            fontWeight: FontWeight.w400,
                            color: s.inkFaint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The header's left half on a sub-page: an arrow and the page's name, one
/// 48-dp target. Tapping it is the system back — the Send flow steps back a
/// page before the screen is left, exactly as the hardware button does.
class _BackButton extends StatelessWidget {
  const _BackButton({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Semantics(
      button: true,
      label: 'Back',
      hint: 'Leaves $title',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _headerRowHeight),
          child: Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Row(
              children: [
                SizedBox(
                  width: AppLayout.minTouchTarget - AppSpacing.sm,
                  child: Center(
                    child: Icon(Icons.arrow_back, size: 22, color: s.ink),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.sectionTitle.copyWith(color: s.ink),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sync state: a dot and a short word. Tap to sync. Runs the first sync on
/// mount when auto-sync is on, exactly as the desktop footer.
///
/// The mark itself is small; its hit box is the full 48-dp header row, so the
/// one control a user taps repeatedly is never under the touch minimum.
class _SyncPill extends StatefulWidget {
  const _SyncPill();

  @override
  State<_SyncPill> createState() => _SyncPillState();
}

class _SyncPillState extends State<_SyncPill> {
  final _bridge = walletBridge;

  @override
  void initState() {
    super.initState();
    scheduleAutoSync(context, _bridge);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Selector<AppState, (SyncState, String?)>(
      selector: (_, st) => (st.syncState, st.syncDetail),
      builder: (context, data, _) {
        final (syncState, syncDetail) = data;
        final isSyncing = syncState == SyncState.syncing;
        final (dotColor, label) = syncStatusPresentation(
          s,
          syncState,
          syncDetail,
          compact: true,
        );
        void sync() => syncActiveWallet(context.read<AppState>(), _bridge);
        return Semantics(
          button: true,
          label: isSyncing ? 'Syncing' : 'Sync now. $label',
          excludeSemantics: true,
          onTap: isSyncing ? null : sync,
          child: SizedBox(
            height: _headerRowHeight,
            child: InkWell(
              onTap: isSyncing ? null : sync,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: AppLayout.minTouchTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _SyncDot(color: dotColor, syncing: isSyncing),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        label,
                        style: AppTypography.eyebrow.copyWith(
                          color: s.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The sync state's mark: a 6 px dot in the state's colour, or a small
/// spinner while a sync is running (the one thing here that is live).
class _SyncDot extends StatelessWidget {
  const _SyncDot({required this.color, required this.syncing});
  final Color color;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppSpacing.md,
      height: AppSpacing.md,
      child: Center(
        child: syncing
            ? CircularProgressIndicator(strokeWidth: 1.5, color: color)
            : Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
      ),
    );
  }
}

// ── Mock-data and regtest strips ──────────────────────────────────────────────

/// Unmissable strip shown whenever the UI runs on the mock bridge (debug
/// fallback after a failed native load): everything on screen is fake data.
/// The one place a solid danger fill is right — a balance nobody owns.
class _MockDataBadge extends StatelessWidget {
  const _MockDataBadge();

  @override
  Widget build(BuildContext context) {
    return const _BadgeStrip(
      color: AppColors.danger,
      text: 'Mock data — wallet engine not loaded',
      phoneText: 'Mock data — engine not loaded',
    );
  }
}

/// One line on a coloured ground, full width, in ink dark enough to read on
/// it. On a phone the copy is the shorter [phoneText], padded at the sides
/// and never wrapped, so the strip is one compact line on every width.
class _BadgeStrip extends StatelessWidget {
  const _BadgeStrip({
    required this.color,
    required this.text,
    required this.phoneText,
  });

  final Color color;
  final String text;
  final String phoneText;

  @override
  Widget build(BuildContext context) {
    final phone = AppSpacing.isPhone(context);
    return Container(
      width: double.infinity,
      color: color,
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.xs,
        horizontal: phone ? AppSpacing.lg : 0,
      ),
      child: Text(
        phone ? phoneText : text,
        textAlign: TextAlign.center,
        maxLines: phone ? 1 : null,
        overflow: phone ? TextOverflow.ellipsis : null,
        style: AppTypography.eyebrow.copyWith(color: AppColors.textPrimary),
      ),
    );
  }
}

/// Strip shown while Liquid runs against a regtest: a local node, or a joined
/// test server's chains (Bitcoin is then on its regtest too). Regtest coins
/// are free and the chain is private, so nothing on screen is the public
/// testnet — the strip says so once, on every screen.
class _RegtestBadge extends StatelessWidget {
  const _RegtestBadge();

  @override
  Widget build(BuildContext context) {
    final lab = context.select<AppState, String?>(
      (s) => s.isBitcoinRegtest || s.liquidNetwork?.testServer != null
          ? s.testServerName
          : null,
    );
    if (lab != null) {
      return _BadgeStrip(
        color: AppColors.warningMuted,
        text:
            'Regtest — Bitcoin and Liquid of test server $lab, not the '
            'public testnets',
        phoneText: 'Regtest — test server, not testnet',
      );
    }
    return const _BadgeStrip(
      color: AppColors.warningMuted,
      text: 'Liquid regtest — local elementsd, not the public testnet',
      phoneText: 'Liquid regtest — local node, not testnet',
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────────────

/// The desktop navigation, on [AppScheme.chrome]: the wallet at the top, the
/// destinations in three groups, the sync state at the foot.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.currentPath,
    required this.expanded,
    required this.onToggle,
  });
  final String currentPath;
  final bool expanded;
  final VoidCallback onToggle;

  /// A settings section route (`/settings/security`) lights the Settings
  /// entry: on desktop the section is a pane inside that one page.
  bool _isActive(String route) =>
      currentPath == route ||
      (route == AppRoutes.settings && _isSettingsSection(currentPath)) ||
      (route == AppRoutes.receive && currentPath == AppRoutes.receiveAddresses);

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    // Only show the Liquid section when the active wallet has Liquid enabled.
    final appState = context.watch<AppState>();
    final showLiquid = appState.activeWalletLiquid;
    // Pure watch-only wallets cannot sign anything — no Send at all.
    final showSend = !appState.isActiveWalletWatchOnly;
    // A peg moves value between the two chains, so it needs both sides. A
    // Liquid-only wallet has no Bitcoin address to peg out to.
    final showPeg = showLiquid && appState.activeWalletBitcoin;
    return Column(
      children: [
        _SidebarHeader(expanded: expanded, onToggle: onToggle),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            children: [
              _section('Wallet', first: true),
              _item(AppRoutes.dashboard, 'Dashboard', Icons.home_outlined),
              if (showSend)
                _item(AppRoutes.send, 'Send', Icons.arrow_outward_outlined),
              _item(AppRoutes.receive, 'Receive', Icons.call_received_outlined),
              _item(AppRoutes.history, 'Activity', Icons.history_outlined),
              _item(
                AppRoutes.utxos,
                'UTXOs',
                Icons.account_balance_wallet_outlined,
              ),
              if (showLiquid) ...[
                _section('Liquid'),
                _item(
                  AppRoutes.liquid,
                  'Liquid assets',
                  Icons.water_drop_outlined,
                ),
                // A loan is a Liquid covenant, so it lives with Liquid.
                // Opt-in: Settings › Templar Protocol (or the connect
                // screen's checkbox) puts it here.
                if (appState.loansEnabled)
                  _item(AppRoutes.loans, 'Loans', Icons.handshake_outlined),
                if (appState.liquidDexEnabled)
                  // Named for the protocol it actually speaks. "Swap" is
                  // reserved for the future Boltz-style Bitcoin <> Liquid <>
                  // Lightning section, which is a different thing entirely.
                  _item(AppRoutes.swap, 'LiquiDEX', Icons.swap_horiz_outlined),
                if (showPeg && appState.pegEnabled)
                  _item(AppRoutes.peg, 'Peg', Icons.swap_vert_outlined),
              ],
              _section('System'),
              _item(AppRoutes.walletInfo, 'Wallet info', Icons.info_outlined),
              _item(AppRoutes.settings, 'Settings', Icons.settings_outlined),
            ],
          ),
        ),
        Divider(color: s.edge, height: 1),
        _SidebarFooter(expanded: expanded),
      ],
    );
  }

  Widget _section(String label, {bool first = false}) =>
      _SidebarSection(label: label, expanded: expanded, first: first);

  Widget _item(String route, String label, IconData icon) => _SidebarItem(
    route: route,
    label: label,
    icon: icon,
    isActive: _isActive(route),
    expanded: expanded,
  );
}

// ── Header ────────────────────────────────────────────────────────────────────

/// The product's name, the collapse control, and the wallet in use — the
/// wallet row is the switcher: it opens the wallet list.
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.expanded, required this.onToggle});
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Selector<AppState, (String?, String?, String?)>(
      selector: (_, st) =>
          (st.activeWalletId, st.activeWalletName, st.activeWalletType),
      builder: (context, wallet, _) {
        final (walletId, walletName, walletType) = wallet;
        final collapse = _ChromeIconButton(
          tooltip: expanded ? 'Collapse sidebar' : 'Expand sidebar',
          icon: expanded
              ? Icons.keyboard_double_arrow_left_outlined
              : Icons.keyboard_double_arrow_right_outlined,
          onTap: onToggle,
        );
        if (!expanded) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              children: [
                collapse,
                const SizedBox(height: AppSpacing.sm),
                Tooltip(
                  message: walletName ?? 'Open wallet',
                  child: InkWell(
                    onTap: () => context.go(AppRoutes.walletPicker),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    child: WalletPlate(
                      icon: walletId != null
                          ? WalletFlags.kindIconForLabel(walletType)
                          : Icons.account_balance_wallet_outlined,
                      tint: walletId != null ? s.accent : null,
                      size: 36,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Row(
                  children: [
                    const AppLogo(size: 28, radius: AppSpacing.radiusSm),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Templar Wallet',
                        style: AppTypography.navItem.copyWith(
                          color: s.ink,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    collapse,
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _WalletSwitcher(
                walletId: walletId,
                walletName: walletName,
                walletType: walletType,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The wallet in use, as a control: one row that opens the wallet list.
class _WalletSwitcher extends StatefulWidget {
  const _WalletSwitcher({
    required this.walletId,
    required this.walletName,
    required this.walletType,
  });
  final String? walletId;
  final String? walletName;
  final String? walletType;

  @override
  State<_WalletSwitcher> createState() => _WalletSwitcherState();
}

class _WalletSwitcherState extends State<_WalletSwitcher> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final open = widget.walletId != null;
    void go() => context.go(AppRoutes.walletPicker);
    return Semantics(
      button: true,
      label: open ? 'Wallet ${widget.walletName ?? ''}' : 'Open wallet',
      hint: 'Opens the wallet list',
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              go();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: go,
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.instant),
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              color: _hover ? s.hover : s.hover.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(
                color: _focus ? s.focus : s.edge,
                width: _focus ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                WalletPlate(
                  icon: open
                      ? WalletFlags.kindIconForLabel(widget.walletType)
                      : Icons.account_balance_wallet_outlined,
                  // The wallet's own colour — the accent while it is open.
                  tint: open ? s.accent : null,
                  size: 40,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        open ? (widget.walletName ?? '…') : 'Open wallet…',
                        style: AppTypography.navItem.copyWith(
                          color: s.ink,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (open && widget.walletType != null)
                        Text(
                          widget.walletType!,
                          style: AppTypography.caption.copyWith(
                            color: s.inkFaint,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.unfold_more_outlined,
                  size: AppSpacing.iconSmall,
                  color: s.inkFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

/// A group's name: closer to its own rows (8) than to the group above (24).
/// Collapsed there is no room for a word, so the gap alone does the grouping.
class _SidebarSection extends StatelessWidget {
  const _SidebarSection({
    required this.label,
    required this.expanded,
    this.first = false,
  });
  final String label;
  final bool expanded;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final top = first ? AppSpacing.lg : AppSpacing.xl;
    if (!expanded) return SizedBox(height: first ? AppSpacing.sm : top);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        top,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        label,
        style: AppTypography.navSection.copyWith(color: s.inkFaint),
      ),
    );
  }
}

// ── Nav item ──────────────────────────────────────────────────────────────────

/// A destination. Rows are 40 tall and 2 apart; icons sit in one column and
/// labels start on one line. The current row is the raised surface with the
/// primary ink — a surface step — and wears the [CurrentMark], a short bar
/// in the accent on its leading edge.
class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.route,
    required this.label,
    required this.icon,
    required this.isActive,
    required this.expanded,
  });

  final String route;
  final String label;
  final IconData icon;
  final bool isActive;
  final bool expanded;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final active = widget.isActive;
    final ink = active || _hover ? s.ink : s.inkSecondary;
    void go() => context.go(widget.route);

    final row = Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        button: true,
        selected: active,
        label: widget.label,
        excludeSemantics: true,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
          onShowHoverHighlight: (v) => setState(() => _hover = v),
          onShowFocusHighlight: (v) => setState(() => _focus = v),
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                go();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: go,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.instant),
              height: AppSpacing.navRowHeight,
              decoration: BoxDecoration(
                color: active
                    ? s.thumb
                    : _hover
                    ? s.hover
                    : s.hover.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              foregroundDecoration: _focus
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: s.focus, width: 2),
                    )
                  : null,
              child: Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  // "You are here": the one mark of the accent on the chrome.
                  CurrentMark(active: active),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.expanded ? AppSpacing.md : 0,
                    ),
                    child: Row(
                      mainAxisAlignment: widget.expanded
                          ? MainAxisAlignment.start
                          : MainAxisAlignment.center,
                      children: [
                        // The current destination's glyph wears the accent,
                        // with the bar on its edge; its label stays ink.
                        Icon(
                          widget.icon,
                          size: AppSpacing.navIcon,
                          color: active ? s.accentGlyph : ink,
                        ),
                        if (widget.expanded) ...[
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              widget.label,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.navItem.copyWith(
                                color: ink,
                                fontWeight: active
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.expanded) return row;
    return Tooltip(message: widget.label, preferBelow: false, child: row);
  }
}

/// A small icon control in the sidebar's chrome: 32 px, quiet until hovered.
class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    required this.tooltip,
    required this.onTap,
    this.icon,
    this.child,
  }) : assert(icon != null || child != null);

  final String tooltip;
  final VoidCallback? onTap;
  final IconData? icon;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      iconSize: AppSpacing.icon,
      icon: child ?? Icon(icon),
    );
  }
}

// ── Sync (shared by the desktop footer and the mobile header) ────────────────

/// Run a full sync of the active wallet and fold the outcome into
/// [AppState]: synced only when every present chain is ok, a partial failure
/// shows as a warning naming the chain, all-failed shows as an error.
Future<void> syncActiveWallet(AppState appState, WalletBridge bridge) async {
  final walletId = appState.activeWalletId;
  if (walletId == null) return;
  appState.setSyncState(SyncState.syncing);
  final sw = Stopwatch()..start();
  try {
    final outcomes = await bridge.syncWallet(walletId);
    sw.stop();
    debugPrint('[sync] done in ${sw.elapsedMilliseconds}ms — $outcomes');
    appState.applySyncOutcomes(outcomes);
  } catch (e) {
    sw.stop();
    debugPrint('[sync] failed after ${sw.elapsedMilliseconds}ms: $e');
    appState.setSyncState(SyncState.error);
    // Screens reload on syncVersion changes; bump even on failure so a
    // dashboard that mounted mid-sync (its _load early-returns while
    // syncing) still gets a chance to render the cached/offline data
    // instead of staying on the shimmer.
    appState.bumpSync();
  }
}

/// Start the first sync once the shell is up, if the user left auto-sync on.
void scheduleAutoSync(BuildContext context, WalletBridge bridge) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    final appState = context.read<AppState>();
    if (appState.autoSync && appState.activeWalletId != null) {
      syncActiveWallet(appState, bridge);
    }
  });
}

/// Dot colour and label for a sync state. The footer shows the chain detail
/// of a partial or failed sync; [compact] is the header's short form.
(Color, String) syncStatusPresentation(
  AppScheme s,
  SyncState state,
  String? detail, {
  bool compact = false,
}) => switch (state) {
  SyncState.synced => (s.success, 'Synced'),
  SyncState.syncing => (s.inkSecondary, 'Syncing…'),
  SyncState.warning => (
    s.warning,
    compact ? 'Partial' : (detail ?? 'Partial sync'),
  ),
  SyncState.error => (
    s.danger,
    compact ? 'Sync error' : (detail ?? 'Sync error'),
  ),
  SyncState.idle => (s.inkFaint, 'Idle'),
};

// ── Footer ────────────────────────────────────────────────────────────────────

/// The foot of the sidebar: the sync state on the left, then sync, theme and
/// lock as three quiet icon controls.
class _SidebarFooter extends StatefulWidget {
  const _SidebarFooter({required this.expanded});
  final bool expanded;

  @override
  State<_SidebarFooter> createState() => _SidebarFooterState();
}

class _SidebarFooterState extends State<_SidebarFooter> {
  final _bridge = walletBridge;

  /// Whether a Lock control belongs here at all. There is nothing to lock
  /// until a vault exists, and offering the button anyway would surface an
  /// engine error as the answer to a click.
  bool _vaultUnlocked = false;

  @override
  void initState() {
    super.initState();
    _refreshVault();
    scheduleAutoSync(context, _bridge);
  }

  Future<void> _refreshVault() async {
    try {
      final v = await _bridge.vaultStatus();
      if (mounted) {
        setState(() => _vaultUnlocked = v.initialized && v.unlocked);
      }
    } catch (_) {
      // No status, no button — never guess that storage is unlocked.
    }
  }

  Future<void> _lock() async {
    await lockVaultAndPrompt(context);
    if (mounted) _refreshVault();
  }

  Future<void> _sync() => syncActiveWallet(context.read<AppState>(), _bridge);

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Selector<AppState, (SyncState, String?, ThemeMode)>(
      selector: (_, st) => (st.syncState, st.syncDetail, st.themeMode),
      builder: (context, data, _) {
        final (syncState, syncDetail, themeMode) = data;
        final isSyncing = syncState == SyncState.syncing;
        final (dotColor, statusLabel) = syncStatusPresentation(
          s,
          syncState,
          syncDetail,
        );
        final themeDark = themeMode == ThemeMode.dark;

        final syncButton = _ChromeIconButton(
          tooltip: isSyncing ? 'Syncing…' : 'Sync now',
          onTap: isSyncing ? null : _sync,
          icon: Icons.sync_outlined,
        );
        final themeButton = _ChromeIconButton(
          tooltip: themeDark ? 'Light mode' : 'Dark mode',
          onTap: context.read<AppState>().toggleTheme,
          icon: themeDark
              ? Icons.light_mode_outlined
              : Icons.dark_mode_outlined,
        );
        final lockButton = _ChromeIconButton(
          tooltip: 'Lock wallet storage',
          onTap: _lock,
          icon: Icons.lock_outlined,
        );

        if (!widget.expanded) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: statusLabel,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: _SyncDot(color: dotColor, syncing: isSyncing),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                syncButton,
                const SizedBox(height: AppSpacing.xs),
                themeButton,
                if (_vaultUnlocked) ...[
                  const SizedBox(height: AppSpacing.xs),
                  lockButton,
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              _SyncDot(color: dotColor, syncing: isSyncing),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  statusLabel,
                  style: AppTypography.body.copyWith(color: s.inkSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              syncButton,
              const SizedBox(width: AppSpacing.xs),
              themeButton,
              if (_vaultUnlocked) ...[
                const SizedBox(width: AppSpacing.xs),
                lockButton,
              ],
            ],
          ),
        );
      },
    );
  }
}

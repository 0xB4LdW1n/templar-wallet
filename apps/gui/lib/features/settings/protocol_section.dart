/// Settings › Templar Protocol — everything the connector does, in one page.
///
/// The groups read top to bottom as the question a user actually has: am I
/// ready, how do I open a request, who is connected, what did I sign, which
/// wallet answers, and what is this.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../services/protocol_portfolio_service.dart';
import '../../services/protocol_store.dart';
import '../../shared/relative_time.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/expander.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../protocol/models/protocol_link.dart';
import '../protocol/models/protocol_records.dart';
import '../protocol/models/protocol_wallet_fit.dart';
import '../protocol/protocol_paste_card.dart';
import '../wallet_picker/models/wallet_summary.dart';
import 'liquid_network_switch.dart';
import 'settings_kit.dart';

/// The protocol's network status, worded once (CLAUDE.md rule 5).
const String kProtocolNetworkStatus =
    'Today the protocol runs on a test regtest; in beta it will run on a '
    'server of ours; then Liquid mainnet.';

/// Where the connector is written down, for anyone who wants the protocol.
const String kProtocolGuideUrl =
    'https://github.com/0xB4LdW1n/TemplarWallet/blob/main/docs/guides/PROTOCOL_CONNECTOR.md';

class ProtocolSection extends StatefulWidget {
  const ProtocolSection({super.key, this.bridge});

  /// Injectable for tests, like [WalletInfoScreen]; the app passes nothing
  /// and gets the process-wide bridge.
  final WalletBridge? bridge;

  @override
  State<ProtocolSection> createState() => _ProtocolSectionState();
}

class _ProtocolSectionState extends State<ProtocolSection> {
  WalletBridge get _bridge => widget.bridge ?? walletBridge;

  LiquidNetworkInfo? _info;
  List<ProtocolConnectedSite> _sites = const [];
  List<ProtocolSignRecord> _history = const [];
  List<WalletSummary> _wallets = const [];
  String? _preferredId;

  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    LiquidNetworkInfo? info;
    String? error;
    try {
      info = await _bridge.getLiquidNetwork();
    } catch (e) {
      error = liquidNetworkErrorText(e);
    }
    List<WalletSummary> wallets = const [];
    try {
      wallets = await _bridge.listWallets();
    } catch (_) {
      // No wallet list, no preference picker — never a broken page.
    }
    final store = ProtocolStore.instance;
    final sites = await store.sites();
    final history = await store.history();
    final preferred = await store.preferredWalletId();
    if (!mounted) return;
    setState(() {
      _info = info;
      _error = error;
      _wallets = wallets;
      _sites = sites;
      _history = history;
      _preferredId = preferred;
      _loading = false;
    });
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  /// The other network: the card offers the one move that exists.
  String? get _otherNetwork => switch (_info?.shortName) {
    'testnet' => 'regtest',
    'regtest' => 'testnet',
    _ => null,
  };

  Future<void> _changeNetwork() async {
    final info = _info;
    final target = _otherNetwork;
    if (info == null || target == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final done = await switchLiquidNetwork(
        context,
        target: target,
        // Regtest keeps the id the engine already knows, else the stock one.
        // The editable field lives in Network, one tap away.
        policyAsset: info.policyAsset.isNotEmpty && info.isRegtest
            ? info.policyAsset
            : info.regtestDefaultPolicyAsset,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (done != null) _info = done.info;
      });
      if (done != null && done.walletClosed && mounted) {
        context.go(AppRoutes.walletPicker);
      }
    } on LiquidNetworkSwitchError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  void _openLink(String link) {
    context.go('${AppRoutes.protocol}?link=${Uri.encodeComponent(link)}');
  }

  Future<void> _forget(ProtocolConnectedSite site) async {
    final ok = await showAppDialog<bool>(
      context,
      builder: (ctx) => PromptDialog(
        title: 'Forget ${site.site}?',
        icon: Icons.link_off_outlined,
        actions: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          DangerButton(
            label: 'Forget',
            icon: Icons.link_off_outlined,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: Text(
          'This removes the record from this device'
          '${site.hasPortfolio ? ' and tells the site to stop answering this wallet\'s loans view' : ' only'}. '
          '${site.site} keeps '
          'the watch-only descriptor of "${site.walletName}" — it can still '
          'see that wallet\'s Liquid balance and history — until you remove '
          'the wallet on the site itself. Nothing here can revoke it.',
          style: AppTypography.body.copyWith(
            color: AppScheme.of(ctx).inkSecondary,
          ),
        ),
      ),
    );
    if (ok != true) return;
    // The token first, while the record still has it; a site that cannot be
    // reached loses the record all the same, and its token dies with the
    // next «Remove this wallet» on the site.
    final service = ProtocolPortfolioService.instance;
    await service.revoke(site);
    service.forget(site.key);
    await ProtocolStore.instance.forgetSite(site.key);
    final sites = await ProtocolStore.instance.sites();
    if (mounted) setState(() => _sites = sites);
  }

  Future<void> _clearHistory() async {
    final ok = await showAppDialog<bool>(
      context,
      builder: (ctx) => PromptDialog(
        title: 'Clear signing history?',
        icon: Icons.delete_outline,
        actions: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          DangerButton(
            label: 'Clear',
            icon: Icons.delete_outline,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: Text(
          'Removes this device\'s list of signing requests. The loans and the '
          'transactions themselves are unaffected — they live on the chain and '
          'on the site.',
          style: AppTypography.body.copyWith(
            color: AppScheme.of(ctx).inkSecondary,
          ),
        ),
      ),
    );
    if (ok != true) return;
    await ProtocolStore.instance.clearHistory();
    if (mounted) setState(() => _history = const []);
  }

  Future<void> _setPreferred(String? id) async {
    await ProtocolStore.instance.setPreferredWalletId(id);
    if (mounted) setState(() => _preferredId = id);
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loansEnabled = context.watch<AppState>().loansEnabled;
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: SizedBox(
            width: AppSpacing.lg,
            height: AppSpacing.lg,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loansEnabled) ...[_loansShortcut(), const SettingsGap()],
        _status(),
        const SettingsGap(),
        ProtocolPasteCard(
          title: 'Open a request',
          subtitle:
              'A Templar Protocol site normally opens Templar by itself when you '
              'click its link. This is the fallback: paste the templar:// link, or '
              'scan the QR the loan page shows.',
          onOpen: _openLink,
        ),
        const SettingsGap(),
        _connectedSites(),
        const SettingsGap(),
        _signingHistory(),
        const SettingsGap(),
        _preferences(),
        const SettingsGap(),
        _howItWorks(),
      ],
    );
  }

  /// The way to the loans themselves once Settings › Advanced has enabled
  /// that optional feature. This page remains the connector's bookkeeping.
  Widget _loansShortcut() {
    final withToken = _sites.where((x) => x.hasPortfolio).length;
    final subtitle = _sites.isEmpty
        ? 'Active loans, payments and pending signatures, once a site is connected'
        : withToken == 0
        ? 'Reconnect a site to see its loans here'
        : 'Active loans, payments and pending signatures from '
              '$withToken connected site${withToken == 1 ? '' : 's'}';
    return ListCard(
      children: [
        ListRow(
          key: const Key('protocol-loans-shortcut'),
          icon: Icons.handshake_outlined,
          title: 'Loans',
          subtitle: subtitle,
          chevron: true,
          onTap: () => context.go(AppRoutes.loans),
        ),
      ],
    );
  }

  Widget _status() {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final info = _info;
    final locked = info?.envLocked ?? false;
    final target = _otherNetwork;
    final error = _error;
    return SettingsGroup(
      label: 'Status',
      blocks: true,
      note: kProtocolNetworkStatus,
      children: [
        if (error != null) SettingsBlock(child: DangerBanner(message: error)),
        if (info == null)
          SettingsBlock(
            child: Text(
              'The wallet engine did not answer, so there is nothing to be '
              'ready for yet.',
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          )
        else ...[
          SettingsBlock(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SettingsDot(s.success),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Ready for ${protocolNetworkLabel(info.network)}'
                        '${info.isRegtest ? ' · policy asset ${protocolShortAsset(info.policyAsset)}' : ''}',
                        style: AppTypography.body.copyWith(color: s.ink),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Requests from a site on another chain are refused, and the '
                  'screen offers the switch. Chain: ${info.backendDescription}',
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ],
            ),
          ),
          if (locked)
            const SettingsBlock(
              child: InfoBanner(
                message:
                    'TEMPLAR_LIQUID_NETWORK fixes the network for this run '
                    'of the app. Unset the variable to change it here.',
              ),
            )
          else if (target != null)
            SettingsBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SecondaryButton(
                    key: const Key('protocol-change-network'),
                    label: 'Change network',
                    icon: Icons.swap_horiz_outlined,
                    isLoading: _busy,
                    isFullWidth: phone,
                    onPressed: _busy ? null : _changeNetwork,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Switches to Liquid $target and closes the open wallet. To '
                    'pick another regtest asset id, use Settings › Network.',
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _connectedSites() {
    final s = AppScheme.of(context);
    return SettingsGroup(
      label: 'Connected sites',
      note:
          'Sites holding a watch-only view of one of your wallets. They can '
          'see that wallet\'s Liquid balance and history and build loan '
          'transactions for it; they cannot spend.',
      blocks: _sites.isEmpty,
      children: _sites.isEmpty
          ? [
              SettingsBlock(
                child: Text(
                  'No site has been connected from this device.',
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ),
            ]
          : [
              for (final site in _sites)
                _SiteRow(site: site, onForget: () => _forget(site)),
            ],
    );
  }

  Widget _signingHistory() {
    final s = AppScheme.of(context);
    return SettingsGroup(
      label: 'Signing history',
      note:
          'The last ${ProtocolStore.historyLimit} requests answered from '
          'this device. What was signed is not kept here — no transaction, no '
          'amounts — only that it happened and how it ended.',
      blocks: _history.isEmpty,
      footer: _history.isEmpty
          ? null
          : Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                key: const Key('protocol-clear-history'),
                label: 'Clear history',
                icon: Icons.delete_outline,
                onPressed: _clearHistory,
              ),
            ),
      children: _history.isEmpty
          ? [
              SettingsBlock(
                child: Text(
                  'Nothing signed yet.',
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ),
            ]
          : [for (final r in _history) _HistoryRow(record: r)],
    );
  }

  Widget _preferences() {
    final s = AppScheme.of(context);
    final usable = _wallets
        .where((w) => protocolWalletFits(w, connect: true))
        .toList();
    return SettingsGroup(
      label: 'Preferred wallet',
      note:
          'The wallet a signing request is answered with, and the one '
          'offered first when a site asks to connect. Every request still asks '
          'for your app password and the confirmation — this only saves the '
          'picking.',
      blocks: usable.isEmpty,
      children: usable.isEmpty
          ? [
              SettingsBlock(
                child: Text(
                  'No wallet qualifies yet: Templar Protocol needs a software '
                  'wallet or a Jade with Liquid enabled.',
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ),
            ]
          : [
              _PreferenceRow(
                label: 'No preference',
                detail: 'Ask every time, or use the open wallet',
                selected: _preferredId == null,
                onTap: () => _setPreferred(null),
              ),
              for (final w in usable)
                _PreferenceRow(
                  label: w.name,
                  detail:
                      '${w.displayType} · ${w.networksLabel}'
                      '${w.masterFingerprint != null ? ' · ${w.masterFingerprint}' : ''}',
                  selected: _preferredId == w.id,
                  onTap: () => _setPreferred(w.id),
                ),
            ],
    );
  }

  Widget _howItWorks() {
    final s = AppScheme.of(context);
    return ExpanderCard(
      key: const Key('protocol-how-it-works'),
      title: 'How it works',
      subtitle:
          'What a connection shares, what a signature does, where the '
          'loan key lives',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Step(
            n: 1,
            title: 'Connect shares a view, never a key',
            body:
                'The site receives the watch-only descriptor of the wallet you '
                'pick, its loan escrow key and one receive address. No secret '
                'leaves this device.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _Step(
            n: 2,
            title: 'Sign shows both readings',
            body:
                'A signing request puts the site\'s summary next to the '
                'wallet\'s own reading of the transaction. You sign after '
                'comparing them; the signature goes to the site, which '
                'broadcasts once every party has signed. Templar never '
                'broadcasts a loan transaction and never stores its PSET.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _Step(
            n: 3,
            title: 'The escrow key is its own account',
            body:
                'It lives at m/2121\'/1\'/0\', below your seed and apart from '
                'the keys that hold your coins, so a loan contract can never '
                'name a spending key of yours.',
          ),
          const SizedBox(height: AppSpacing.lg),
          HoverRow(
            onTap: () => launchUrl(
              Uri.parse(kProtocolGuideUrl),
              mode: LaunchMode.externalApplication,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: AppSpacing.icon,
                    color: s.inkSecondary,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'docs/guides/PROTOCOL_CONNECTOR.md',
                      style: AppTypography.mono.copyWith(color: s.ink),
                    ),
                  ),
                  Icon(
                    Icons.open_in_new_outlined,
                    size: AppSpacing.iconSmall,
                    color: s.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Rows ──────────────────────────────────────────────────────────────────────

/// A connected site: its name, its origin in mono, what it holds, and the
/// way to forget it.
class _SiteRow extends StatelessWidget {
  const _SiteRow({required this.site, required this.onForget});
  final ProtocolConnectedSite site;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final shared = [
      if (site.sharedDescriptor) 'watch-only descriptor',
      if (site.escrowFingerprint.isNotEmpty)
        'escrow key ${site.escrowFingerprint}',
      if (site.receiveAddress.isNotEmpty) 'one receive address',
    ].join(' · ');
    final forget = GhostButton(
      label: 'Forget',
      icon: Icons.link_off_outlined,
      onPressed: onForget,
    );

    return Padding(
      padding: const EdgeInsets.all(kListPad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListIconTile(icon: Icons.language_outlined),
          const SizedBox(width: kListGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  site.site,
                  style: AppTypography.bodyOf(context).copyWith(color: s.ink),
                ),
                Text(
                  '${site.origin} · ${protocolNetworkLabel(site.network)}',
                  style: AppTypography.monoSmall.copyWith(
                    color: s.inkSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                KvRow(label: 'Wallet', value: site.walletName),
                KvRow(
                  label: 'Connected',
                  value: relativeTimeShort(site.connectedAt.toLocal()),
                ),
                if (shared.isNotEmpty) KvRow(label: 'Shared', value: shared),
                if (site.receiveAddress.isNotEmpty)
                  KvRow(label: 'Address', value: site.receiveAddress),
                if (phone) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Align(alignment: Alignment.centerLeft, child: forget),
                ],
              ],
            ),
          ),
          if (!phone) ...[const SizedBox(width: AppSpacing.md), forget],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.record});
  final ProtocolSignRecord record;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    // A status dot where the outcome is a fact worth seeing at a glance;
    // the quiet ones (refused, cancelled, expired) carry the word alone.
    final colour = switch (record.outcome) {
      ProtocolSignOutcome.signed => s.success,
      ProtocolSignOutcome.refused => s.inkFaint,
      ProtocolSignOutcome.cancelled => s.inkFaint,
      ProtocolSignOutcome.expired => s.inkFaint,
      ProtocolSignOutcome.failed => s.danger,
    };
    final title = [
      if (record.loanRef.isNotEmpty) record.loanRef,
      if (record.action.isNotEmpty) protocolActionLabel(record.action),
    ].join(' · ');

    return SettingsRow(
      icon: Icons.draw_outlined,
      title: title.isEmpty ? 'Signing request' : title,
      subtitle:
          '${record.site}'
          '${record.walletName.isNotEmpty ? ' · ${record.walletName}' : ''}'
          ' · ${relativeTimeShort(record.at.toLocal())}',
      trailing: TagChip(label: record.outcome.label, color: colour),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Semantics(
      selected: selected,
      child: SettingsRow(
        // The radio stands in the glyph column, so names start on one line.
        leading: Icon(
          selected
              ? Icons.radio_button_checked_outlined
              : Icons.radio_button_unchecked_outlined,
          size: AppSpacing.icon,
          color: selected ? s.ink : s.inkFaint,
        ),
        title: label,
        subtitle: detail,
        onTap: onTap,
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.body});
  final int n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.body.copyWith(color: s.ink)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                body,
                style: AppTypography.caption.copyWith(color: s.inkSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

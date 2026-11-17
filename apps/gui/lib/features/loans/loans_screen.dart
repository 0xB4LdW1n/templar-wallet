// Loans — the wallet's view of its Templar Protocol loans, fed by the site
// (`GET /connector/portfolio`, CONNECTOR.md §7).
//
// The wallet knows nothing about a loan on its own: it signs what the site
// asks and keeps a thin history. This screen asks the site, with the token
// the connect callback handed back, and shows the answer as it is — role,
// state, next step, time left, amounts — plus the two things the wallet can
// do about it: sign the pending request in-app, or open the loan on the
// site. Nothing here is stored; the site is the ledger and this is a window.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../services/protocol_link_service.dart';
import '../../services/protocol_portfolio_service.dart';
import '../../services/protocol_store.dart';
import '../../shared/relative_time.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/privacy.dart';
import '../../shared/widgets/segmented_switch.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../protocol/models/protocol_link.dart';
import '../protocol/models/protocol_portfolio.dart';
import '../protocol/models/protocol_records.dart';
import 'loan_overview_card.dart';
import 'lending_site.dart';

class LoansScreen extends StatefulWidget {
  const LoansScreen({super.key, this.service, this.store});

  /// Injectable for tests; the app passes nothing and gets the singletons.
  final ProtocolPortfolioService? service;
  final ProtocolStore? store;

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen> {
  ProtocolPortfolioService get _service =>
      widget.service ?? ProtocolPortfolioService.instance;
  ProtocolStore get _store => widget.store ?? ProtocolStore.instance;

  List<ProtocolConnectedSite> _sites = const [];
  String? _siteKey;
  bool _sitesLoaded = false;
  String? _walletId;

  /// The loan whose one-time link is being fetched (`0` for the site root),
  /// so that card's button waits; null when nothing is in flight.
  int? _opening;

  /// Why the last «Open on Templar Protocol» did not open, in words.
  String? _openError;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onService);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSites());
  }

  @override
  void dispose() {
    _service.removeListener(_onService);
    super.dispose();
  }

  void _onService() {
    if (mounted) setState(() {});
  }

  ProtocolConnectedSite? get _site {
    for (final s in _sites) {
      if (s.key == _siteKey) return s;
    }
    return null;
  }

  Future<void> _loadSites() async {
    final walletId = context.read<AppState>().activeWalletId;
    _walletId = walletId;
    final sites = walletId == null
        ? <ProtocolConnectedSite>[]
        : await _store.sitesForWallet(walletId);
    if (!mounted) return;
    // The site with a token first; a pre-v1.1 one only when it is all there is.
    final preferred =
        sites.where((s) => s.hasPortfolio).firstOrNull ?? sites.firstOrNull;
    setState(() {
      _sites = sites;
      _siteKey = sites.any((s) => s.key == _siteKey)
          ? _siteKey
          : preferred?.key;
      _sitesLoaded = true;
    });
    final site = _site;
    if (site != null &&
        site.hasPortfolio &&
        _service.snapshot(site.key) == null) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    var site = _site;
    if (site == null) return;
    // The record may have changed under us (a reconnect stored a token).
    final fresh = (await _store.sitesForWallet(
      site.walletId,
    )).where((s) => s.key == site!.key).firstOrNull;
    if (fresh != null) site = fresh;
    if (!mounted) return;
    if (!site.hasPortfolio) {
      await _loadSites();
      return;
    }
    try {
      await _service.refresh(site);
    } on ProtocolPortfolioError {
      // The snapshot carries it; a 401 also dropped the token, so re-read.
      if (mounted) await _loadSites();
    }
  }

  void _sign(ProtocolPendingRequest request) {
    // The same door a browser link comes through: the request screen fetches
    // the request, shows both readings and asks for the gate and the
    // password. Nothing is signed from here.
    ProtocolLinkService.instance.inject(request.link);
  }

  void _details(ProtocolLoan loan) {
    final site = _site;
    if (site == null) return;
    context.go(AppRoutes.loanDetailLocation(site.key, loan.id));
  }

  void _act(ProtocolLoan loan) {
    final pending = loan.pendingRequest;
    if (pending != null && !pending.isExpired()) {
      _sign(pending);
      return;
    }
    _open(loan);
  }

  /// «Open on Templar Protocol» (§8): asks the site for a one-time link that
  /// lands the browser on the loan — or on the site's front page — already
  /// inside this wallet's session, and hands that link to the system
  /// browser. The bearer token never leaves the request header; the link
  /// itself is single use and dies in two minutes.
  Future<void> _open(ProtocolLoan? loan) async {
    final site = _site;
    if (site == null || _opening != null) return;
    if (!site.hasPortfolio) {
      await _openSite();
      return;
    }
    final id = loan?.id ?? 0;
    setState(() {
      _opening = id;
      _openError = null;
    });
    try {
      final link = await _service.openLink(
        site,
        to: loan == null ? '/' : '/loans/${loan.id}',
      );
      if (!mounted) return;
      final launched = await launchUrl(
        link,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        setState(
          () => _openError =
              'The browser did not open. The link is single use and expires in '
              'two minutes — press the button again for a fresh one.',
        );
      }
    } on ProtocolPortfolioError catch (e) {
      if (!mounted) return;
      setState(() => _openError = e.message);
      if (e.kind == ProtocolPortfolioErrorKind.needsReconnect) {
        // The token died on the site's side; the record has dropped it too.
        await _loadSites();
      }
    } catch (e) {
      if (mounted) setState(() => _openError = 'Could not open the site: $e');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _openSite() async {
    final site = _site;
    if (site == null) return;
    final uri = Uri.tryParse(site.origin);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final pad = AppSpacing.pagePadding(context);
    final st = context.watch<AppState>();
    final site = _site;
    final snap = site == null ? null : _service.snapshot(site.key);
    final portfolio = snap?.portfolio;
    final walletName = st.activeWalletName ?? site?.walletName ?? '';
    final network =
        portfolio?.network ?? site?.network ?? st.liquidNetwork?.network ?? '';
    final subtitle = site == null
        ? 'Templar Protocol'
        : [
            site.site,
            if (walletName.isNotEmpty) walletName,
            if (network.isNotEmpty) protocolNetworkLabel(network),
          ].join(' · ');
    final loading = snap?.loading ?? false;
    final live = site != null && site.hasPortfolio;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Loans',
          subtitle: subtitle,
          actions: [
            const PrivacyToggle(),
            _HeaderIconButton(
              key: const Key('loans-settings'),
              tooltip: 'Templar Protocol settings',
              icon: Icons.settings_outlined,
              onPressed: () => context.go(AppRoutes.settingsProtocol),
            ),
            if (live) ...[
              _HeaderIconButton(
                key: const Key('loans-refresh'),
                tooltip: 'Refresh',
                icon: Icons.refresh_outlined,
                busy: loading,
                onPressed: loading ? null : _refresh,
              ),
              if (phone)
                _HeaderIconButton(
                  key: const Key('loans-open-root'),
                  tooltip: 'Open on Templar Protocol',
                  icon: Icons.open_in_new_outlined,
                  busy: _opening == 0,
                  onPressed: _opening != null ? null : () => _open(null),
                )
              else
                SecondaryButton(
                  key: const Key('loans-open-root'),
                  label: 'Open on Templar Protocol',
                  icon: Icons.open_in_new_outlined,
                  isLoading: _opening == 0,
                  onPressed: _opening != null ? null : () => _open(null),
                ),
            ],
          ],
        ),
        if (_openError != null) ...[
          DangerBanner(
            title: 'Could not open the site',
            message: _openError!,
            action: GhostButton(
              label: 'Dismiss',
              onPressed: () => setState(() => _openError = null),
            ),
          ),
          SizedBox(height: phone ? AppSpacing.md : AppSpacing.lg),
        ],
        if (_sites.length > 1) ...[
          SegmentedSwitch<String>(
            selected: _siteKey ?? _sites.first.key,
            expand: true,
            dense: phone,
            onChanged: (k) {
              setState(() => _siteKey = k);
              final s = _site;
              if (s != null &&
                  s.hasPortfolio &&
                  _service.snapshot(s.key) == null) {
                _refresh();
              }
            },
            options: [
              for (final s in _sites) SegOption(value: s.key, label: s.site),
            ],
          ),
          SizedBox(height: phone ? AppSpacing.md : AppSpacing.lg),
        ],
      ],
    );

    return Scaffold(
      body: PageBackground.flat(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth + 2 * pad,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                pad,
                phone ? AppSpacing.lg : pad,
                pad,
                pad + AppSpacing.xl,
              ),
              children: [
                header,
                ..._body(site: site, snap: snap, phone: phone),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body({
    required ProtocolConnectedSite? site,
    required ProtocolPortfolioSnapshot? snap,
    required bool phone,
  }) {
    if (!_sitesLoaded) return const [_Spinner()];
    if (site == null) {
      final st = context.watch<AppState>();
      final lending = labLendingSite(st);
      final settings = SecondaryButton(
        label: 'Templar Protocol settings',
        onPressed: () => context.go(AppRoutes.settingsProtocol),
        isFullWidth: phone,
      );
      return [
        _Empty(
          key: const Key('loans-no-site'),
          icon: Icons.link_off_outlined,
          title: 'No site connected to this wallet',
          body: _walletId == null
              ? 'Open a wallet first.'
              : lending != null
              ? '${st.testServerName ?? 'The test server'} runs a Templar '
                    'Protocol lending site on its regtest. Open it and click '
                    '"Connect Templar Wallet" there: once connected, its loans '
                    'show up here.'
              : 'A Templar Protocol site learns about this wallet when you click '
                    '"Connect Templar Wallet" there. Once connected, its loans show '
                    'up here.',
          action: lending == null || _walletId == null
              ? settings
              : Column(
                  crossAxisAlignment: phone
                      ? CrossAxisAlignment.stretch
                      : CrossAxisAlignment.center,
                  children: [
                    PrimaryButton(
                      key: const Key('loans-open-lending-site'),
                      label: kOpenLendingSite,
                      icon: Icons.open_in_new_outlined,
                      isFullWidth: phone,
                      onPressed: () => openLabLendingSite(context, lending),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      lending.toString(),
                      style: AppTypography.monoSmall.copyWith(
                        color: AppScheme.of(context).inkFaint,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    settings,
                  ],
                ),
        ),
      ];
    }
    final portfolio = snap?.portfolio;
    final error = snap?.error;
    if (!site.hasPortfolio) {
      return [
        _Empty(
          key: const Key('loans-reconnect'),
          icon: Icons.sync_problem_outlined,
          title: 'Reconnect to see your loans',
          body:
              error?.kind == ProtocolPortfolioErrorKind.needsReconnect &&
                  error != null
              ? error.message
              : '${site.site} was connected before this wallet could show '
                    'loans, or has since revoked its access. Connect it again '
                    'from the site: the loans you already have come back with it.',
          action: PrimaryButton(
            key: const Key('loans-open-site'),
            label: 'Open ${site.site}',
            icon: Icons.open_in_new_outlined,
            onPressed: _openSite,
            isFullWidth: phone,
          ),
        ),
      ];
    }
    if (portfolio == null) {
      if (error != null) {
        return [
          _Empty(
            key: const Key('loans-error'),
            icon: Icons.cloud_off_outlined,
            title: switch (error.kind) {
              ProtocolPortfolioErrorKind.rateLimited => 'Asked too often',
              ProtocolPortfolioErrorKind.offline => 'The site did not answer',
              _ => 'Could not load the loans',
            },
            body: error.message,
            action: SecondaryButton(
              key: const Key('loans-retry'),
              label: 'Try again',
              onPressed: _refresh,
              isFullWidth: phone,
            ),
          ),
        ];
      }
      return const [_Spinner()];
    }

    final actionRequired = portfolio.actionRequiredLoans();
    final active = portfolio.activeLoans();
    final completed = portfolio.closedLoans;
    final offers = portfolio.offers;
    final s = AppScheme.of(context);
    final gap = SizedBox(height: phone ? AppSpacing.xl : AppSpacing.xxl);
    final updatedAt = snap?.fetchedAt ?? portfolio.asOf;
    final stale = error != null;
    final updating = snap?.loading ?? false;

    Widget rows(List<ProtocolLoan> loans, {required bool acting}) => LoanList(
      children: [
        for (var i = 0; i < loans.length; i++)
          LoanOverviewCard(
            loan: loans[i],
            updatedAt: updatedAt,
            stale: stale,
            updating: updating,
            primaryEmphasis: acting && i == 0,
            busy: acting && _opening == loans[i].id,
            onPrimary: acting ? () => _act(loans[i]) : () => _details(loans[i]),
            onOpen: () => _details(loans[i]),
          ),
      ],
    );

    return [
      if (error != null) ...[
        WarningBanner(
          title: 'Showing the last answer',
          message:
              '${error.message} Below is what ${site.site} said '
              '${snap?.fetchedAt != null ? relativeTimeShort(snap!.fetchedAt!) : 'earlier'}.',
        ),
        SizedBox(height: phone ? AppSpacing.md : AppSpacing.lg),
      ],
      _SummaryStrip(portfolio: portfolio, phone: phone),
      gap,
      ListSectionLabel(label: 'Action required · ${actionRequired.length}'),
      if (actionRequired.isEmpty)
        const _EmptySection(
          key: Key('loans-no-action'),
          title: 'Nothing needs you now',
          body:
              'Pending signatures, installments, claims and covenant renewals appear here',
        )
      else
        rows(actionRequired, acting: true),
      gap,
      ListSectionLabel(label: 'Active · ${active.length}'),
      if (active.isEmpty)
        const _EmptySection(
          key: Key('loans-no-active'),
          title: 'No waiting loans',
          body:
              'Loans waiting for a deadline, confirmation or another party appear here',
        )
      else
        rows(active, acting: false),
      gap,
      ListSectionLabel(label: 'Completed · ${completed.length}'),
      if (completed.isEmpty)
        const _EmptySection(
          key: Key('loans-no-completed'),
          title: 'No completed loans',
          body:
              'Repaid, defaulted and liquidated loans remain available as history',
        )
      else
        rows(completed, acting: false),
      if (offers.isNotEmpty) ...[
        gap,
        ListSectionLabel(label: 'Your offers · ${offers.length}'),
        ListCard(children: [for (final o in offers) _OfferRow(offer: o)]),
      ],
      SizedBox(height: phone ? AppSpacing.lg : AppSpacing.xl),
      Text(
        'As of ${_asOf(portfolio.asOf)} · block ${protocolGroupDigits('${portfolio.tipHeight}')}'
        '${portfolio.wallet.label.isNotEmpty ? ' · known to ${site.site} as "${portfolio.wallet.label}"' : ''}'
        '${portfolio.wallet.escrowFingerprint.isNotEmpty ? ' · loan key ${portfolio.wallet.escrowFingerprint}' : ''}',
        key: const Key('loans-as-of'),
        style: AppTypography.caption.copyWith(color: s.inkFaint),
      ),
    ];
  }

  static String _asOf(DateTime t) {
    final l = t.toLocal();
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    final ss = l.second.toString().padLeft(2, '0');
    return '${relativeTimeShort(l)} ($hh:$mm:$ss)';
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────────

/// What the site holds for this wallet, as figures before any row is read:
/// open loans, signatures waiting, offers, closed loans. Numbers only — a
/// label, the figure, one line of context — sharing one height.
class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.portfolio, required this.phone});
  final ProtocolPortfolio portfolio;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final p = portfolio;
    final open = p.openLoans.length;
    final toSign = p.pendingCount;
    final asBorrower = p.openLoans.where((l) => l.role == 'borrower').length;
    final asLender = open - asBorrower;
    final repaid = p.closedLoans
        .where((l) => l.state == ProtocolLoanState.repaid)
        .length;
    final stats = <_Stat>[
      _Stat(
        label: 'Active loans',
        value: '$open',
        context: open == 0
            ? 'None open'
            : [
                if (asBorrower > 0) '$asBorrower borrowing',
                if (asLender > 0) '$asLender lending',
              ].join(' · '),
      ),
      _Stat(
        label: 'To sign',
        value: '$toSign',
        context: toSign > 0 ? 'The site waits for you' : 'Nothing waiting',
      ),
      _Stat(
        label: 'Open offers',
        value: '${p.offers.length}',
        context: p.offers.isEmpty
            ? 'None on the market'
            : 'Yours on the market',
      ),
      _Stat(
        label: 'Closed',
        value: '${p.closedLoans.length}',
        context: p.closedLoans.isEmpty ? 'No history yet' : '$repaid repaid',
      ),
    ];
    final s = AppScheme.of(context);
    Widget cell(_Stat st) => Padding(
      padding: EdgeInsets.all(
        phone ? AppSpacing.cardPaddingSmall : AppSpacing.cardPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            st.label,
            style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            st.value,
            style: AppTypography.balanceMediumOf(
              context,
            ).copyWith(color: s.ink),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            st.context,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ],
      ),
    );
    Widget divider({bool vertical = true}) => vertical
        ? VerticalDivider(width: 1, thickness: 1, color: s.edge)
        : Divider(height: 1, thickness: 1, color: s.edge);

    // One card, the figures side by side with hairlines between them; a
    // phone folds the four into two rows of two.
    final List<Widget> lines = phone
        ? [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cell(stats[0])),
                  divider(),
                  Expanded(child: cell(stats[1])),
                ],
              ),
            ),
            divider(vertical: false),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cell(stats[2])),
                  divider(),
                  Expanded(child: cell(stats[3])),
                ],
              ),
            ),
          ]
        : [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0) divider(),
                    Expanded(child: cell(stats[i])),
                  ],
                ],
              ),
            ),
          ];
    return Container(
      key: const Key('loans-summary'),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: lines,
      ),
    );
  }
}

class _Stat {
  const _Stat({
    required this.label,
    required this.value,
    required this.context,
  });
  final String label;
  final String value;
  final String context;
}

/// A chrome icon button in the page header: the privacy eye's metrics (a
/// 28 px square on desktop, 48 dp on a phone), the icon in the secondary
/// ink, a small spinner in its place while [busy].
class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final side = phone
        ? AppLayout.minTouchTarget
        : AppSpacing.controlHeightSmall;
    final glyph = phone ? 22.0 : AppSpacing.icon;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: side, height: side),
      iconSize: glyph,
      icon: busy
          ? SizedBox.square(
              dimension: AppSpacing.iconSmall,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: s.inkSecondary,
              ),
            )
          : Icon(icon, color: s.inkSecondary),
    );
  }
}

class _OfferRow extends StatelessWidget {
  const _OfferRow({required this.offer});
  final ProtocolOffer offer;

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final side = switch (o.side) {
      'lend' => 'Lending',
      'borrow' => 'Borrowing',
      '' => 'Offer',
      final other => other,
    };
    final terms = [
      if (o.rateBps != null) protocolBpsLabel(o.rateBps!),
      if (o.durationBlocks != null)
        '${protocolGroupDigits('${o.durationBlocks}')} blocks',
      if (o.collateral != null) 'against ${o.collateral!.display}',
    ].join(' · ');
    return ListRow(
      icon: o.side == 'lend'
          ? Icons.call_made_outlined
          : Icons.call_received_outlined,
      title:
          '$side${o.principal != null ? ' ${o.principal!.display}' : ''} · #${o.id}',
      subtitle: terms.isEmpty ? null : terms,
      trailing: o.state.isNotEmpty ? QuietTag(label: o.state) : null,
      chevron: o.url != null,
      onTap: o.url == null
          ? null
          : () => launchUrl(o.url!, mode: LaunchMode.externalApplication),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.xxl),
    child: Center(
      child: SizedBox.square(
        dimension: AppSpacing.xl,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppScheme.of(context).inkSecondary,
        ),
      ),
    ),
  );
}

/// A page with nothing to list: centred in the content column, a neutral
/// outlined glyph, the fact as a title, the explanation, the way forward.
class _Empty extends StatelessWidget {
  const _Empty({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: AppSpacing.xl, color: s.inkFaint),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: AppTypography.sectionTitle.copyWith(color: s.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                body,
                style: AppTypography.bodyOf(
                  context,
                ).copyWith(color: s.inkSecondary),
                textAlign: TextAlign.center,
              ),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.xl),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// An empty section of the list: one quiet card in the place its rows
/// would take, so the three sections keep their rhythm.
class _EmptySection extends StatelessWidget {
  const _EmptySection({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return LoanList(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodyOf(context).copyWith(color: s.ink),
              ),
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

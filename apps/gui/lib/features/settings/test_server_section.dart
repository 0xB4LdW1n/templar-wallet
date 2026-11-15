/// Settings › Network & Sync › Test server: join a Templar test server
/// ("testlab") with one URL, see whether it still runs the chain the wallet
/// joined, re-join after a reset, leave.
///
/// What the server put in use (order book, Liquid backend, Bitcoin network)
/// is shown by the Nodes card below it, which states every server with where
/// it came from; this card only states the server itself.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/code_box.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'liquid_network_switch.dart' show liquidNetworkErrorText;
import 'test_server_switch.dart';

class TestServerCard extends StatefulWidget {
  const TestServerCard({super.key, this.bridge});

  /// Tests pass a stub; the app uses the live bridge.
  final WalletBridge? bridge;

  @override
  State<TestServerCard> createState() => _TestServerCardState();
}

class _TestServerCardState extends State<TestServerCard> {
  final _url = TextEditingController();
  String? _urlProblem;
  String? _error;
  bool _busy = false;
  bool _checking = false;
  bool _loaded = false;

  WalletBridge get _bridge => widget.bridge ?? walletBridge;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await _bridge.getTestServer();
      if (!mounted) return;
      context.read<AppState>().setTestServerInfo(info);
      setState(() {
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _error = liquidNetworkErrorText(e);
        });
      }
    }
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final info = await _bridge.getTestServer(check: true);
      if (!mounted) return;
      final st = context.read<AppState>()
        ..setTestServerInfo(info)
        ..setTestServerStale(info.isStale);
      st.testServerChecked = true;
    } catch (e) {
      if (mounted) setState(() => _error = liquidNetworkErrorText(e));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _join({String? url, bool rejoin = false}) async {
    final target = url ?? _url.text.trim();
    final problem = testServerUrlProblem(target);
    if (problem != null) {
      setState(() => _urlProblem = problem);
      return;
    }
    setState(() {
      _error = null;
      _urlProblem = null;
    });
    try {
      final done = await joinTestServer(
        context,
        target,
        rejoin: rejoin,
        bridge: widget.bridge,
        onConfirmed: () => setState(() => _busy = true),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (done == null) return;
      _url.clear();
      // A closed wallet cannot stay on screen with the other chain's coins.
      if (done.walletClosed) context.go(AppRoutes.walletPicker);
    } on TestServerError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  Future<void> _leave() async {
    setState(() => _error = null);
    try {
      final done = await leaveTestServer(
        context,
        bridge: widget.bridge,
        onConfirmed: () => setState(() => _busy = true),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (done?.walletClosed ?? false) context.go(AppRoutes.walletPicker);
    } on TestServerError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final info = st.testServer;
    final profile = info?.profile;
    return FormCard(
      title: 'Test server',
      subtitle:
          'A Templar test server runs its own Bitcoin and Liquid regtest, a '
          'faucet and a swap order book. Join one with its URL; everything '
          'else comes from the server.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            DangerBanner(message: _error!),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (info == null && !_loaded)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            if (info?.active.envLocked ?? false) ...[
              InfoBanner(
                message:
                    'TEMPLAR_LIQUID_NETWORK fixes Liquid to '
                    '${st.liquidNetworkName} for this session. A test server '
                    'can still be joined, but its regtest chains apply only '
                    'once the variable is unset.',
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            if (profile == null) _joinForm() else _joined(st, info!, profile),
          ],
        ],
      ),
    );
  }

  Widget _joinForm() {
    final phone = AppLayout.isPhone(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const Key('test-server-url'),
          controller: _url,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          style: AppTypography.mono,
          onChanged: (_) {
            if (_urlProblem != null) setState(() => _urlProblem = null);
          },
          onSubmitted: (_) => _join(),
          decoration: InputDecoration(
            labelText: 'Test server URL',
            hintText: 'http://127.0.0.1:8096',
            errorText: _urlProblem,
            errorMaxLines: 2,
            prefixIcon: phone ? null : const Icon(Icons.dns_outlined, size: 16),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SecondaryButton(
          label: 'Join',
          icon: Icons.login_rounded,
          isLoading: _busy,
          onPressed: _busy ? null : () => _join(),
          isFullWidth: phone,
        ),
      ],
    );
  }

  Widget _joined(AppState st, TestServerInfo info, TestServerProfile profile) {
    final s = AppScheme.of(context);
    final check = info.check;
    final stale = st.testServerStale || info.isStale;
    final String status;
    if (check == null) {
      status = 'Not checked this session.';
    } else if (!check.reachable) {
      status = 'Did not answer the last check.';
    } else if (stale) {
      status = 'Answered: its chain was reset.';
    } else {
      status = 'Answered: same chain as when you joined.';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          profile.name.isNotEmpty ? profile.name : profile.baseUrl,
          style: AppTypography.label.copyWith(color: s.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          status,
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        CopyRow(label: 'Server', value: profile.baseUrl, singleLine: true),
        if (stale) ...[
          const SizedBox(height: AppSpacing.md),
          WarningBanner(
            title: 'The test chain was reset',
            message:
                'The test server now runs a new chain, so what this wallet '
                'stored no longer matches it. Re-join to switch to the new '
                'chain; regtest balances are synced again from scratch.',
            action: SecondaryButton(
              label: 'Re-join',
              icon: Icons.restart_alt_rounded,
              dense: true,
              onPressed: _busy
                  ? null
                  : () => _join(url: profile.baseUrl, rejoin: true),
            ),
          ),
        ] else if (check != null && !check.reachable) ...[
          const SizedBox(height: AppSpacing.md),
          WarningBanner(
            title: 'Test server unreachable',
            message:
                '${check.error ?? 'It did not answer.'} The wallet keeps using '
                'the servers it stored when you joined; try again later.',
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            GhostButton(
              label: _checking ? 'Checking…' : 'Check now',
              icon: Icons.refresh_rounded,
              onPressed: _checking || _busy ? null : _check,
            ),
            SecondaryButton(
              label: 'Leave',
              icon: Icons.logout_rounded,
              isLoading: _busy,
              onPressed: _busy ? null : _leave,
            ),
          ],
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../app/app_version.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../vault/lock_action.dart';
import '../vault/vault_setup_sheet.dart';
import '../../services/auto_lock.dart';
import '../../services/biometric_unlock_service.dart';
import '../../services/price_service.dart';
import '../../services/protocol_store.dart';
import '../../services/cosigner_label_store.dart';
import '../../services/wallet_customization_store.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cosigner_label_editor.dart';
import '../../shared/widgets/cosigner_ring.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/seal_mark.dart';
import '../../shared/widgets/segmented_switch.dart';
import 'backup_verify_section.dart';
import 'biometric_unlock_tile.dart';
import 'liquid_network_switch.dart';
import 'protocol_section.dart';
import 'seed_phrase_section.dart';
import 'settings_kit.dart';
import 'test_server_section.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'package:url_launcher/url_launcher.dart';

/// A settings section. Each is a route of its own (see [AppRoutes]): on a
/// phone that is what makes a section a sub-page, with the shell's back
/// arrow and the system back both returning to the settings list.
enum SettingsSection {
  network('Network', Icons.wifi_outlined, AppRoutes.settingsNetwork),
  // The icon is the fallback only: Templar Protocol wears the brand's cross
  // ([glyph]), which no icon font carries.
  protocol('Templar Protocol', Icons.link_outlined, AppRoutes.settingsProtocol),
  security('Security', Icons.lock_outline, AppRoutes.settingsSecurity),
  appearance(
    'Appearance',
    Icons.palette_outlined,
    AppRoutes.settingsAppearance,
  ),
  advanced('Advanced', Icons.tune_outlined, AppRoutes.settingsAdvanced),
  about('About', Icons.info_outline, AppRoutes.settingsAbout);

  const SettingsSection(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;

  /// The section's glyph at [size] in [color]: its icon, or — for Templar
  /// Protocol — the Templar cross, drawn in the row's ink like any icon.
  Widget glyph(double size, Color color) => this == SettingsSection.protocol
      ? CrossGlyph(size: size, color: color)
      : Icon(icon, size: size, color: color);
}

/// The section pane's measure: settings rows wider than this stop scanning
/// as one line of label, description and control.
const double _kPaneMaxWidth = 720;

/// The desktop rail beside the section pane.
const double _kRailWidth = 200;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.section});

  /// The section to open. Null shows the settings list on a phone and the
  /// first section on desktop.
  final SettingsSection? section;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Desktop: the pane on show. The rail switches it locally; a section
  /// route only picks the one to start on.
  late SettingsSection _section = widget.section ?? SettingsSection.network;

  @override
  void didUpdateWidget(SettingsScreen old) {
    super.didUpdateWidget(old);
    final next = widget.section;
    if (next != null && next != old.section) _section = next;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    // Phones: the settings root is a list of sections, and a section is a
    // page of its own under the shell's "‹ Section" header. Desktop keeps
    // its two panes whatever the window size.
    if (AppLayout.isPhone(context)) {
      final section = widget.section;
      if (section == null) return const _SettingsHome();
      final p = AppSpacing.pagePadding(context);
      // No Scaffold of its own: MobileShell supplies the Scaffold, the
      // background and the SafeArea (a nested Scaffold would show every
      // SnackBar twice).
      return ColoredBox(
        color: s.canvas,
        child: ListView(
          // Foot room: the last thing on a section page otherwise ends flush
          // against the system navigation bar.
          padding: EdgeInsets.fromLTRB(p, p, p, p + AppSpacing.xxl),
          children: [_contentOf(section)],
        ),
      );
    }
    final p = AppSpacing.pagePadding(context);
    return Scaffold(
      backgroundColor: s.canvas,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The rail: quiet, the main sidebar's row grammar, the page's name
          // at its head. The selected section is a surface step, never red.
          Container(
            width: _kRailWidth,
            decoration: BoxDecoration(
              color: s.canvas,
              border: Border(right: BorderSide(color: s.edge)),
            ),
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              p,
              AppSpacing.md,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.md,
                    bottom: AppSpacing.xl,
                  ),
                  child: Text(
                    'Settings',
                    style: AppTypography.pageTitle.copyWith(color: s.ink),
                  ),
                ),
                for (final section in SettingsSection.values)
                  _RailRow(
                    section: section,
                    selected: section == _section,
                    onTap: () => setState(() => _section = section),
                  ),
              ],
            ),
          ),
          // The pane starts straight with its groups: the rail already says
          // which section this is.
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(p),
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _kPaneMaxWidth),
                    child: _contentOf(_section),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentOf(SettingsSection section) => switch (section) {
    SettingsSection.network => _NetworkSection(),
    SettingsSection.protocol => const ProtocolSection(),
    SettingsSection.security => _SecuritySection(),
    SettingsSection.appearance => _AppearanceSection(),
    SettingsSection.advanced => const _AdvancedSection(),
    SettingsSection.about => _AboutSection(),
  };
}

/// One entry of the desktop rail: 36 tall, 2 apart, an 18 px outlined glyph
/// and the label — the main sidebar's row, one level down.
class _RailRow extends StatefulWidget {
  const _RailRow({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final SettingsSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailRow> createState() => _RailRowState();
}

class _RailRowState extends State<_RailRow> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final active = widget.selected;
    final ink = active || _hover ? s.ink : s.inkSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        button: true,
        selected: active,
        label: widget.section.label,
        excludeSemantics: true,
        child: FocusableActionDetector(
          mouseCursor: SystemMouseCursors.click,
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
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.instant),
              curve: AppMotion.settle,
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
                  CurrentMark(active: active),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        // The section on show wears the accent on its glyph,
                        // as the sidebar's current row does.
                        widget.section.glyph(
                          AppSpacing.navIcon,
                          active ? s.accentGlyph : ink,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            widget.section.label,
                            maxLines: 1,
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Phone: the settings list ──────────────────────────────────────────────────
//
// Groups, not one long card. Each group is a subject — what protects the
// wallet, how it looks, what it talks to — and inside it the switches a user
// actually flips sit inline, while the rows that need a whole page carry a
// chevron to one. Wallet info is the first row: it is the wallet's public
// face and has no tab of its own.

class _SettingsHome extends StatefulWidget {
  const _SettingsHome();

  @override
  State<_SettingsHome> createState() => _SettingsHomeState();
}

class _SettingsHomeState extends State<_SettingsHome> {
  /// Whether a Lock row belongs here: there is nothing to lock until a vault
  /// exists and is open.
  bool _vaultUnlocked = false;

  /// Whether this device has a fingerprint sensor at all. Asked here rather
  /// than inside the row so the card never loses a row after it is drawn.
  bool _hasBiometrics = false;

  /// How many sites hold a watch-only view, for the Templar Protocol row's subtitle.
  /// Null until read — the row then states the network alone rather than
  /// claiming "no site connected" before looking.
  int? _protocolSites;

  @override
  void initState() {
    super.initState();
    _refreshVault();
    _refreshBiometrics();
    _refreshProtocol();
  }

  Future<void> _refreshProtocol() async {
    final sites = await ProtocolStore.instance.sites();
    if (mounted) setState(() => _protocolSites = sites.length);
  }

  /// "Liquid regtest · 2 sites connected" — what the section would say.
  String _protocolSubtitle(AppState st) {
    final net = st.liquidNetwork?.shortName ?? 'testnet';
    final n = _protocolSites;
    if (n == null) return 'Liquid $net';
    if (n == 0) return 'Liquid $net · no site connected';
    return 'Liquid $net · $n site${n == 1 ? '' : 's'} connected';
  }

  Future<void> _refreshVault() async {
    try {
      final v = await walletBridge.vaultStatus();
      if (mounted) {
        setState(() => _vaultUnlocked = v.initialized && v.unlocked);
      }
    } catch (_) {
      // No status, no row — never guess that storage is unlocked.
    }
  }

  Future<void> _refreshBiometrics() async {
    if (!BiometricUnlockService.platformSupported) return;
    try {
      final a = await BiometricUnlockService.instance.availability();
      if (mounted) {
        setState(() => _hasBiometrics = a != BiometricAvailability.unavailable);
      }
    } catch (_) {
      // No sensor answer, no row.
    }
  }

  Future<void> _lock() async {
    await lockVaultAndPrompt(context);
    if (mounted) _refreshVault();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final st = context.watch<AppState>();
    final theme = switch (st.themeMode) {
      ThemeMode.dark => 'Dark',
      ThemeMode.light => 'Light',
      ThemeMode.system => 'System',
    };
    final liquidNet = st.liquidNetwork?.shortName ?? 'testnet';

    return ColoredBox(
      color: s.canvas,
      child: ListView(
        padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
        children: [
          const PageHeader(title: 'Settings'),
          SettingsGroup(
            label: 'Wallet',
            children: [
              ListRow(
                icon: Icons.key_outlined,
                title: 'Wallet info',
                subtitle: 'Keys, descriptors, export',
                chevron: true,
                onTap: () => context.go(AppRoutes.walletInfo),
              ),
            ],
          ),
          const SettingsGap(),
          SettingsGroup(
            label: 'Security',
            children: [
              if (_hasBiometrics) const BiometricUnlockTile(compact: true),
              const AutoLockRow(),
              ListRow(
                icon: Icons.lock_outline,
                title: 'Vault and backup',
                subtitle: 'Passphrase, backup check, seed',
                chevron: true,
                onTap: () => context.go(SettingsSection.security.route),
              ),
              if (_vaultUnlocked)
                ListRow(
                  icon: Icons.lock_clock_outlined,
                  title: 'Lock now',
                  subtitle: 'Ask for the passphrase again',
                  onTap: _lock,
                ),
            ],
          ),
          const SettingsGap(),
          // There is no "Reduce effects" row: the app has no blur for it to
          // switch off, and a switch that changes nothing is a lie. The
          // preference and its setter stay in AppState.
          SettingsGroup(
            label: 'Appearance',
            children: [
              ListRow(
                icon: Icons.palette_outlined,
                title: 'Theme and units',
                subtitle:
                    '$theme · ${st.fiatCurrency} · '
                    '${st.useSats ? 'sats' : 'BTC'}',
                chevron: true,
                onTap: () => context.go(SettingsSection.appearance.route),
              ),
            ],
          ),
          const SettingsGap(),
          SettingsGroup(
            label: 'Network',
            children: [
              ListRow(
                icon: Icons.wifi_outlined,
                title: 'Nodes and explorers',
                subtitle: st.testServerName != null
                    ? 'Test server ${st.testServerName} · Liquid $liquidNet'
                    : 'Liquid $liquidNet · test server, nodes',
                chevron: true,
                onTap: () => context.go(SettingsSection.network.route),
              ),
              ListRow(
                glyph: (size, color) => CrossGlyph(size: size, color: color),
                title: 'Templar Protocol',
                subtitle: _protocolSubtitle(st),
                chevron: true,
                onTap: () => context.go(SettingsSection.protocol.route),
              ),
              ListRow(
                icon: Icons.sync_outlined,
                title: 'Auto-sync',
                subtitle: 'Sync this wallet when the app opens',
                trailing: ListSwitch(
                  value: st.autoSync,
                  onChanged: st.setAutoSync,
                  semanticLabel: 'Auto-sync on startup',
                ),
              ),
            ],
          ),
          const SettingsGap(),
          SettingsGroup(
            label: 'Advanced',
            children: [
              ListRow(
                icon: Icons.tune_outlined,
                title: 'Optional features',
                subtitle: _advancedSummary(st),
                chevron: true,
                onTap: () => context.go(SettingsSection.advanced.route),
              ),
            ],
          ),
          const SettingsGap(),
          SettingsGroup(
            label: 'About',
            children: [
              ListRow(
                icon: Icons.info_outline,
                title: 'Templar Wallet',
                subtitle:
                    'v$kAppVersion · '
                    '${st.isBitcoinRegtest || st.isLiquidRegtest ? 'Regtest' : 'Testnet'}',
                chevron: true,
                onTap: () => context.go(SettingsSection.about.route),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _advancedSummary(AppState state) {
  final enabled = <String>[
    if (state.liquidDexEnabled) 'LiquiDEX',
    if (state.pegEnabled) 'Peg',
    if (state.loansEnabled) 'Loans',
  ];
  return enabled.isEmpty
      ? 'All optional features are off'
      : enabled.join(' · ');
}

/// Optional product surfaces live behind one explicit gate. Switching one on
/// only makes its routes visible; every signing and broadcast confirmation is
/// still performed by the feature itself.
class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SettingsGroup(
      label: 'Features',
      note:
          'Off by default. Enabling a feature reveals its screens only; it '
          'does not share keys, sign, broadcast, or move funds.',
      children: [
        ListRow(
          key: const Key('advanced-liquiddex'),
          icon: Icons.swap_horiz_outlined,
          title: 'LiquiDEX',
          subtitle: 'Atomic swaps between Liquid assets',
          trailing: ListSwitch(
            value: state.liquidDexEnabled,
            onChanged: state.setLiquidDexEnabled,
            semanticLabel: 'Show LiquiDEX',
          ),
        ),
        ListRow(
          key: const Key('advanced-peg'),
          icon: Icons.swap_vert_outlined,
          title: 'Peg',
          subtitle: 'Move value between Bitcoin and Liquid',
          trailing: ListSwitch(
            value: state.pegEnabled,
            onChanged: state.setPegEnabled,
            semanticLabel: 'Show Peg',
          ),
        ),
        ListRow(
          key: const Key('advanced-loans'),
          icon: Icons.handshake_outlined,
          title: 'Loans',
          subtitle: 'Templar Protocol positions and requests',
          trailing: ListSwitch(
            value: state.loansEnabled,
            onChanged: state.setLoansEnabled,
            semanticLabel: 'Show Loans',
          ),
        ),
      ],
    );
  }
}

// ── Delete wallet ─────────────────────────────────────────────────────────────
//
// Last group on the Security page, on its own. Deleting a wallet is the one
// action here that can lose money: it says so with its verb, its icon and the
// danger ink on its button, and the paragraph under it says what is at stake.

class _DangerZone extends StatelessWidget {
  const _DangerZone({required this.onDelete});
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final button = DangerButton(
      label: 'Delete wallet',
      icon: Icons.delete_outline,
      onPressed: onDelete,
      isFullWidth: phone,
    );
    return SettingsGroup(
      label: 'Danger zone',
      note:
          'Removes the wallet and its keys from this app. There is no undo '
          'and no copy anywhere else. If you do not hold a written backup of '
          'the recovery phrase, every coin in it becomes unspendable — by you '
          'and by everyone.',
      footer: phone ? button : null,
      children: [
        SettingsRow(
          icon: Icons.delete_outline,
          tint: s.danger,
          title: 'Delete this wallet',
          subtitle: 'Removes the wallet and its keys from this app',
          trailing: phone ? null : button,
        ),
      ],
    );
  }
}

/// The confirmation itself: a forced pause, then a typed phrase.
///
/// A checkbox and an OK button can both be cleared by muscle memory, and the
/// old dialog could be dismissed in two clicks from a screen the user was only
/// browsing. Two gates fix that, and they fix different halves of the problem:
/// the countdown buys time to actually read the warning, and typing
/// "confirm delete" makes the confirmation impossible to hit by accident.
class _DeleteWalletDialog extends StatefulWidget {
  const _DeleteWalletDialog({required this.walletName});
  final String walletName;

  @override
  State<_DeleteWalletDialog> createState() => _DeleteWalletDialogState();
}

class _DeleteWalletDialogState extends State<_DeleteWalletDialog> {
  static const String _phrase = 'confirm delete';
  static const int _waitSeconds = 5;

  final _ctrl = TextEditingController();
  Timer? _tick;
  int _remaining = _waitSeconds;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  bool get _waiting => _remaining > 0;

  bool get _phraseOk => _ctrl.text.trim().toLowerCase() == _phrase;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return AppDialog(
      icon: Icon(
        Icons.warning_amber_outlined,
        color: s.danger,
        size: AppSpacing.icon,
      ),
      title: Text(
        'Delete "${widget.walletName}"?',
        style: AppTypography.sectionTitle.copyWith(color: s.ink),
      ),
      content: SizedBox(
        width: phone ? double.infinity : 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DangerBanner(
              message:
                  'This deletes the only copy of this wallet on this '
                  '${Platform.isAndroid ? 'device' : 'computer'}. '
                  'Without a written backup of the recovery phrase, the funds '
                  'are gone permanently — nobody, including Templar, can bring '
                  'them back.',
            ),
            const SizedBox(height: AppSpacing.lg),
            // The pause. A filling ring reads as "wait", where a plain
            // disabled button reads as "broken".
            if (_waiting) ...[
              Row(
                children: [
                  SizedBox(
                    width: AppSpacing.iconSmall,
                    height: AppSpacing.iconSmall,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: (_waitSeconds - _remaining) / _waitSeconds,
                      color: s.inkSecondary,
                      backgroundColor: s.edge,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Read the warning. You can confirm in $_remaining second'
                      '${_remaining == 1 ? '' : 's'}.',
                      style: AppTypography.bodySmall.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                'Type $_phrase to confirm',
                style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _ctrl,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                style: AppTypography.mono.copyWith(color: s.ink),
                decoration: InputDecoration(
                  hintText: _phrase,
                  hintStyle: AppTypography.mono.copyWith(color: s.inkFaint),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_phraseOk) Navigator.of(context).pop(true);
                },
              ),
            ],
          ],
        ),
      ),
      // In a sheet the actions land in an end-aligned Wrap: full width, they
      // stack as two bars instead of two right-hugging chips.
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
          isFullWidth: phone,
        ),
        DangerButton(
          label: 'Delete wallet',
          icon: Icons.delete_outline,
          onPressed: (!_waiting && _phraseOk)
              ? () => Navigator.of(context).pop(true)
              : null,
          isFullWidth: phone,
        ),
      ],
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _ctrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _ctrl.text;
    final c = _confirmCtrl.text;
    if (p.isNotEmpty && p != c) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    Navigator.of(context).pop(p); // empty string = remove password
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return PromptDialog(
      title: 'Wallet password',
      icon: Icons.lock_outline,
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          isFullWidth: phone,
        ),
        PrimaryButton(label: 'Set', onPressed: _submit, isFullWidth: phone),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Leave blank to remove the password',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          PasswordField(controller: _ctrl, label: 'New password'),
          const SizedBox(height: AppSpacing.lg),
          PasswordField(
            controller: _confirmCtrl,
            label: 'Confirm password',
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

// ── Network ───────────────────────────────────────────────────────────────────

/// Which explorer row is open for editing.
enum _ExplorerEdit { none, bitcoin, liquid }

class _NetworkSection extends StatefulWidget {
  @override
  State<_NetworkSection> createState() => _NetworkSectionState();
}

class _NetworkSectionState extends State<_NetworkSection> {
  late TextEditingController _btcExplorer;
  late TextEditingController _liquidExplorer;
  _ExplorerEdit _editing = _ExplorerEdit.none;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _btcExplorer = TextEditingController(text: state.btcExplorerUrl);
    _liquidExplorer = TextEditingController(text: state.liquidExplorerUrl);
  }

  @override
  void dispose() {
    _btcExplorer.dispose();
    _liquidExplorer.dispose();
    super.dispose();
  }

  void _saveExplorers() {
    final state = context.read<AppState>();
    state.setBtcExplorerUrl(_btcExplorer.text.trim());
    state.setLiquidExplorerUrl(_liquidExplorer.text.trim());
    setState(() => _editing = _ExplorerEdit.none);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Explorer URLs saved'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Leaves the row as it was: the field goes back to the saved value.
  void _cancelEdit(AppState state) {
    _btcExplorer.text = state.btcExplorerUrl;
    _liquidExplorer.text = state.liquidExplorerUrl;
    setState(() => _editing = _ExplorerEdit.none);
  }

  /// One explorer: its saved value in mono with an Edit control, or — while
  /// it is being edited — the field and its Save.
  Widget _explorerRow({
    required AppState state,
    required _ExplorerEdit which,
    required String title,
    required String value,
    required String hint,
    required TextEditingController ctrl,
  }) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    if (_editing != which) {
      return SettingsRow(
        icon: Icons.explore_outlined,
        title: title,
        subtitle: value.isEmpty ? hint : value,
        mono: true,
        trailing: GhostButton(
          label: 'Edit',
          icon: Icons.edit_outlined,
          onPressed: () => setState(() => _editing = which),
        ),
      );
    }
    final actions = [
      GhostButton(label: 'Cancel', onPressed: () => _cancelEdit(state)),
      const SizedBox(width: AppSpacing.sm),
      SecondaryButton(
        label: 'Save',
        icon: Icons.check_outlined,
        onPressed: _saveExplorers,
      ),
    ];
    return SettingsBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: ctrl,
            autofocus: true,
            style: AppTypography.mono.copyWith(color: s.ink),
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (_) => _saveExplorers(),
          ),
          const SizedBox(height: AppSpacing.md),
          if (phone)
            Row(children: actions)
          else
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final state = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The phone settings root already carries this exact switch as a
        // list row, one tap away — drawing it here too puts the same control
        // on screen twice.
        if (!phone) ...[
          SettingsGroup(
            label: 'Sync',
            children: [
              ListRow(
                icon: Icons.sync_outlined,
                title: 'Auto-sync on startup',
                subtitle: 'Sync the active wallet when the app opens',
                trailing: ListSwitch(
                  value: state.autoSync,
                  onChanged: state.setAutoSync,
                  semanticLabel: 'Auto-sync on startup',
                ),
              ),
            ],
          ),
          const SettingsGap(),
        ],
        const _LiquidNetworkCard(),
        const SettingsGap(),
        const TestServerCard(),
        const SettingsGap(),
        _NodesGroup(state: state),
        const SettingsGap(),
        SettingsGroup(
          label: 'Block explorers',
          note:
              'Used for "View on Explorer" links in transaction history. A '
              'regtest chain has no public explorer, so its links are hidden.',
          blocks: _editing != _ExplorerEdit.none,
          children: [
            _explorerRow(
              state: state,
              which: _ExplorerEdit.bitcoin,
              title: 'Bitcoin explorer',
              value: state.btcExplorerUrl,
              hint: 'https://mempool.space/testnet',
              ctrl: _btcExplorer,
            ),
            _explorerRow(
              state: state,
              which: _ExplorerEdit.liquid,
              title: 'Liquid explorer',
              value: state.liquidExplorerUrl,
              hint: 'https://blockstream.info/liquidtestnet',
              ctrl: _liquidExplorer,
            ),
          ],
        ),
        const SettingsGap(),
        const SettingsGroup(
          label: 'Privacy',
          children: [
            ListRow(
              icon: Icons.shield_outlined,
              title: 'Tor',
              subtitle: 'Not yet implemented',
              trailing: QuietTag(label: 'Coming soon'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The servers the engine talks to, each with where it came from (a test
/// server, an environment variable, an app setting or the built-in default),
/// as the engine reports them in `active`. Read-only.
class _NodesGroup extends StatelessWidget {
  const _NodesGroup({required this.state});
  final AppState state;

  static String _from(String source) => 'from ${endpointSourceLabel(source)}';

  static Widget _row(String title, String value) => SettingsRow(
    icon: Icons.dns_outlined,
    title: title,
    subtitle: value,
    mono: true,
    wrap: true,
    trailing: SettingsCopyButton(value: value),
  );

  @override
  Widget build(BuildContext context) {
    final active = state.testServer?.active;
    return SettingsGroup(
      label: 'Nodes',
      note:
          'The servers in use and where each comes from. A test server sets '
          'them all; TEMPLAR_LIQUID_ELECTRUM_URL, TEMPLAR_ELEMENTS_RPC_URL and '
          'the TEMPLAR_SWAP_* variables override single ones.',
      children: active == null
          ? [
              // No answer from the engine yet: never a testnet default that
              // may not be the one in use.
              _row('Bitcoin Electrum', 'Loading…'),
              _row(
                'Liquid chain',
                state.liquidNetwork?.backendDescription ?? 'Loading…',
              ),
            ]
          : [
              _row(
                'Bitcoin ${active.bitcoin.shortName} · '
                '${_from(active.bitcoin.source)}',
                active.bitcoin.electrumUrl,
              ),
              _row(
                'Liquid ${active.liquid.network.replaceFirst('liquid-', '')}'
                ' · ${_from(active.liquid.backendSource)}',
                active.liquid.backendDescription,
              ),
              _row(
                'Order book · ${_from(active.orderbook.origin.source)}',
                active.orderbook.origin.url,
              ),
            ],
    );
  }
}

/// Liquid network selector: the public testnet or a local Elements regtest
/// (what the Templar Protocol runs locally). Switching closes the open wallet
/// on the engine side, so the card sends the user back to the picker.
class _LiquidNetworkCard extends StatefulWidget {
  const _LiquidNetworkCard();

  @override
  State<_LiquidNetworkCard> createState() => _LiquidNetworkCardState();
}

class _LiquidNetworkCardState extends State<_LiquidNetworkCard> {
  LiquidNetworkInfo? _info;
  String? _error;
  bool _busy = false;
  String _choice = 'testnet';
  final _policyAsset = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _policyAsset.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await walletBridge.getLiquidNetwork();
      if (!mounted) return;
      context.read<AppState>().setLiquidNetworkInfo(info);
      setState(() {
        _adopt(info);
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = liquidNetworkErrorText(e));
    }
  }

  void _adopt(LiquidNetworkInfo info) {
    _info = info;
    _choice = info.shortName;
    _policyAsset.text = info.isRegtest
        ? info.policyAsset
        : info.regtestDefaultPolicyAsset;
  }

  /// A test server is joined: its regtest is the only regtest, and the
  /// engine takes its policy asset from the server.
  bool get _onLab => _info?.testServer != null;

  /// Whether the form differs from what the engine is on.
  bool get _dirty {
    final info = _info;
    if (info == null) return false;
    if (_choice != info.shortName) return true;
    return _choice == 'regtest' &&
        !_onLab &&
        _policyAsset.text.trim().toLowerCase() !=
            info.policyAsset.toLowerCase();
  }

  Future<void> _apply() async {
    final info = _info;
    if (info == null || !_dirty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The confirmation, the switch and the closing of the open wallet are
      // shared with the Templar Protocol request screen (liquid_network_switch.dart).
      final done = await switchLiquidNetwork(
        context,
        target: _choice,
        policyAsset: _onLab ? null : _policyAsset.text,
      );
      if (!mounted) return;
      if (done == null) {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _info = done.info;
        _busy = false;
      });
      // The shell must not keep showing the other network's balances.
      if (done.walletClosed) context.go(AppRoutes.walletPicker);
    } on LiquidNetworkSwitchError catch (e) {
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
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    // Joining or leaving a test server (the card below) moves Liquid too:
    // follow the shared state once the engine has answered.
    final shared = context.select<AppState, LiquidNetworkInfo?>(
      (a) => a.liquidNetwork,
    );
    if (shared != null && _info != null && !identical(shared, _info)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_busy) setState(() => _adopt(shared));
      });
    }
    final info = _info;
    final locked = info?.envLocked ?? false;
    final track = SegmentedSwitch<String>(
      options: const [
        SegOption(value: 'testnet', label: 'Testnet'),
        SegOption(value: 'regtest', label: 'Regtest'),
      ],
      selected: _choice,
      onChanged: _busy ? (_) {} : (v) => setState(() => _choice = v),
      expand: phone,
    );

    final children = <Widget>[
      if (_error != null) SettingsBlock(child: DangerBanner(message: _error!)),
      if (info == null && _error == null)
        const SettingsBlock(
          child: Center(
            child: SizedBox(
              width: AppSpacing.lg,
              height: AppSpacing.lg,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      if (info != null) ...[
        SettingsRow(
          icon: Icons.water_drop_outlined,
          title: 'Network',
          subtitle: 'Now ${info.shortName}',
          // A ~200 px track beside its row on desktop; a phone gives the
          // choice the card's whole width, in a block of its own below.
          trailing: locked
              ? const QuietTag(label: 'Fixed')
              : (phone ? null : track),
        ),
        if (locked)
          const SettingsBlock(
            child: InfoBanner(
              message:
                  'Fixed by TEMPLAR_LIQUID_NETWORK for this session. '
                  'Unset the variable to change it here.',
            ),
          )
        else ...[
          if (phone) SettingsBlock(child: track),
          if (_choice == 'regtest' && _onLab)
            SettingsBlock(
              child: Text(
                'Regtest is the joined test server\'s chain.',
                style: AppTypography.caption.copyWith(color: s.inkSecondary),
              ),
            ),
          if (_choice == 'regtest' && !_onLab)
            SettingsBlock(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Regtest LBTC asset id',
                    style: AppTypography.eyebrow.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _policyAsset,
                    enabled: !_busy,
                    onChanged: (_) => setState(() {}),
                    style: AppTypography.mono.copyWith(color: s.ink),
                    decoration: InputDecoration(
                      hintText: info.regtestDefaultPolicyAsset,
                      helperText:
                          'Policy asset of your node. The stock liquidregtest '
                          'id is prefilled; elements-cli dumpassetlabels '
                          'prints yours.',
                      helperMaxLines: 3,
                    ),
                  ),
                ],
              ),
            ),
          if (_dirty || _busy)
            SettingsBlock(
              child: Column(
                crossAxisAlignment: phone
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.end,
                children: [
                  const WarningBanner(
                    message:
                        'Switching closes the open wallet. Reopen it and sync — '
                        'until then no Liquid balance is shown for the new '
                        'network.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SecondaryButton(
                    label: 'Apply',
                    icon: Icons.swap_horiz_outlined,
                    isLoading: _busy,
                    onPressed: _dirty && !_busy ? _apply : null,
                    isFullWidth: phone,
                  ),
                ],
              ),
            ),
        ],
      ],
    ];

    return SettingsGroup(
      label: 'Liquid network',
      blocks: true,
      note: context.watch<AppState>().testServerName != null
          ? 'Testnet is the public Liquid test network. Regtest is the '
                'joined test server\'s Liquid regtest, beside its Bitcoin '
                'regtest: its faucet pays free coins.'
          : 'Testnet is the public Liquid test network. Regtest is a local '
                'elementsd (what the Templar Protocol runs locally): instant '
                'blocks, free coins.',
      children: children,
    );
  }
}

// ── Security ──────────────────────────────────────────────────────────────────

class _SecuritySection extends StatefulWidget {
  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
  WalletCustomization? _custom;
  VaultStatus? _vault;
  String _dataDir = '';
  String? _dataDirError;

  /// True when the active wallet stores a seed on this device (software only).
  bool _hasSeed = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadVault();
    _checkSeed();
    _resolveDir();
  }

  Future<void> _checkSeed() async {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return;
    try {
      final info = await walletBridge.getWalletInfo(walletId);
      if (mounted) setState(() => _hasSeed = info.hasSeed);
    } catch (_) {
      // No seed card when the wallet can't be inspected.
    }
  }

  Future<void> _resolveDir() async {
    try {
      // The engine is the source of truth for where wallet data lives
      // (state.rs resolves it via dirs-next). Reconstructing the path on the
      // Dart side drifted from it on Windows, so always ask the engine.
      final dir = await walletBridge.getDataDir();
      if (mounted) setState(() => _dataDir = dir);
    } catch (e) {
      if (mounted) {
        setState(
          () => _dataDirError =
              'Could not read the data directory from the wallet engine: $e',
        );
      }
    }
  }

  Future<void> _openDir() async {
    if (_dataDir.isEmpty) return;
    // file:// URI — Linux (xdg-open), macOS (Finder), Windows (Explorer).
    final uri = Uri.file(_dataDir);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _deleteWallet() async {
    final appState = context.read<AppState>();
    final walletId = appState.activeWalletId;
    if (walletId == null) return;
    final name = appState.activeWalletName ?? 'this wallet';

    final confirmed = await showAppDialog<bool>(
      context,
      barrierDismissible: false,
      builder: (_) => _DeleteWalletDialog(walletName: name),
    );
    if (confirmed != true || !mounted) return;

    try {
      await walletBridge.deleteWallet(walletId);
      await WalletCustomizationStore.instance.delete(walletId);
      // The names go with the wallet — a new wallet must never inherit
      // a deleted one's labels through a recycled id.
      await CosignerLabelStore.instance.delete(walletId);
      // Same reason: the connected-site records name a wallet id, and a
      // recycled one must not inherit a deleted wallet's connections.
      await ProtocolStore.instance.forgetWallet(walletId);
      if (!mounted) return;
      appState.setActiveWallet(null);
      // Picker redirects to the welcome screen when no wallets remain.
      context.go(AppRoutes.walletPicker);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not delete wallet: $e')));
      }
    }
  }

  Future<void> _load() async {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return;
    final c = await WalletCustomizationStore.instance.load(walletId);
    if (mounted) setState(() => _custom = c);
  }

  Future<void> _loadVault() async {
    try {
      final v = await walletBridge.vaultStatus();
      if (mounted) setState(() => _vault = v);
    } catch (_) {
      // The group shows an unavailable state when the status can't be read.
    }
  }

  Future<void> _setupVault() async {
    final done = await showAppDialog<bool>(
      context,
      builder: (_) => const VaultSetupSheet(),
    );
    if (done != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Wallet storage is now encrypted'),
        duration: Duration(seconds: 2),
      ),
    );
    await _loadVault();
  }

  Future<void> _lockNow() async {
    await lockVaultAndPrompt(context);
    if (mounted) _loadVault();
  }

  void _pushUnlock() {
    pushVaultUnlock(
      context,
      onUnlocked: () {
        if (mounted) _loadVault();
      },
    );
  }

  /// Encryption: one row stating the vault's state, the one control that
  /// acts on it, and the full paragraph under the card. While storage is
  /// unencrypted, "Set passphrase" is the page's one filled control: it is
  /// the thing this page needs the user to do.
  Widget get _vaultGroup {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final vault = _vault;
    final String statusText;
    final Widget? action;
    final IconData rowIcon;
    final String rowState;
    final Color? dot;
    final VoidCallback? rowTap;
    if (vault == null) {
      statusText = 'Encryption status unavailable';
      action = null;
      rowIcon = Icons.help_outline;
      rowState = 'Status unavailable';
      dot = null;
      rowTap = null;
    } else if (!vault.initialized) {
      statusText =
          'Wallet seeds are currently stored unencrypted on this '
          '${Platform.isAndroid ? 'device' : 'computer'}. '
          'Set a passphrase to encrypt them at rest. You will be asked for it '
          'every time the app starts. If you lose the passphrase, the wallets '
          'in this app cannot be recovered without their seed-phrase backups.\n\n'
          'Until you do, Templar will not create or restore a wallet whose '
          'recovery phrase would be kept here.';
      action = PrimaryButton(
        label: 'Set passphrase',
        icon: Icons.shield_outlined,
        onPressed: _setupVault,
        isFullWidth: phone,
      );
      rowIcon = Icons.shield_outlined;
      rowState = 'Not encrypted — set a passphrase';
      dot = s.warning;
      rowTap = _setupVault;
    } else if (vault.unlocked) {
      statusText =
          'Wallet storage is encrypted at rest. The vault is unlocked for '
          'this session.';
      action = SecondaryButton(
        label: 'Lock now',
        icon: Icons.lock_outline,
        onPressed: _lockNow,
      );
      rowIcon = Icons.lock_outline;
      rowState = 'Encrypted · unlocked this session';
      dot = s.success;
      rowTap = _lockNow;
    } else {
      statusText = 'Wallet storage is encrypted and locked';
      action = SecondaryButton(
        label: 'Unlock',
        icon: Icons.lock_open_outlined,
        onPressed: _pushUnlock,
      );
      rowIcon = Icons.lock_open_outlined;
      rowState = 'Encrypted · locked';
      dot = s.success;
      rowTap = _pushUnlock;
    }
    final unencrypted = vault != null && !vault.initialized;
    return SettingsGroup(
      label: 'Encryption',
      note: statusText,
      // Phone: the row itself is the way in, except while unencrypted —
      // then the one thing this page asks for is a full-width button too.
      footer: phone && unencrypted ? action : null,
      children: [
        SettingsRow(
          icon: rowIcon,
          title: 'Wallet storage',
          subtitle: rowState,
          dot: dot,
          chevron: phone && rowTap != null,
          onTap: phone ? rowTap : null,
          trailing: phone ? null : action,
        ),
      ],
    );
  }

  Future<void> _setPassword() async {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null || _custom == null) return;
    final result = await showAppDialog<String>(
      context,
      builder: (_) => const _PasswordDialog(),
    );
    if (result == null || !mounted) return;
    final hash = result.isEmpty
        ? null
        : WalletCustomizationStore.hashPassword(result);
    final updated = _custom!.copyWith(passwordHash: hash);
    await WalletCustomizationStore.instance.save(updated);
    if (mounted) {
      setState(() => _custom = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(hash == null ? 'Password removed' : 'Password set'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget get _passwordGroup {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final custom = _custom;
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null || custom == null) {
      return const SettingsGroup(
        label: 'Wallet password',
        blocks: true,
        children: [
          SettingsBlock(
            child: InfoBanner(
              message:
                  'No wallet open. Open a wallet from the wallet picker first.',
            ),
          ),
        ],
      );
    }
    final isSet = custom.passwordHash != null;
    return SettingsGroup(
      label: 'Wallet password',
      note: isSet
          ? 'Entering this wallet requires the password'
          : 'Anyone with access to the app can open this wallet',
      children: [
        SettingsRow(
          icon: Icons.password_outlined,
          title: 'Password',
          subtitle: isSet ? 'Set' : 'Not set',
          dot: isSet ? s.success : null,
          chevron: phone,
          onTap: phone ? _setPassword : null,
          trailing: phone
              ? null
              : SecondaryButton(
                  label: isSet ? 'Change or remove' : 'Set password',
                  onPressed: _setPassword,
                ),
        ),
      ],
    );
  }

  Widget get _storageGroup {
    final s = AppScheme.of(context);
    final error = _dataDirError;
    return SettingsGroup(
      label: 'Storage',
      children: [
        SettingsRow(
          icon: Icons.folder_outlined,
          title: 'Wallet data directory',
          subtitle: error ?? (_dataDir.isEmpty ? '…' : _dataDir),
          subtitleColor: error != null ? s.danger : null,
          mono: error == null,
          wrap: true,
          trailing: error != null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SettingsCopyButton(value: _dataDir, tooltip: 'Copy path'),
                    // No file manager handles a file:// directory on Android.
                    if (!Platform.isAndroid) ...[
                      const SizedBox(width: AppSpacing.xs),
                      SecondaryButton(
                        label: 'Open',
                        icon: Icons.folder_open_outlined,
                        onPressed: _dataDir.isEmpty ? null : _openDir,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final walletId = context.watch<AppState>().activeWalletId;
    final phone = AppLayout.isPhone(context);
    // One page, ordered from "protects everything" down to "destroys
    // everything": the vault, how it opens, the backup, the seed, the
    // wallet's own password, where it all lives, and deleting it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _vaultGroup,
        // Fingerprint (Touch ID on a Mac) in place of the passphrase at
        // launch. The group brings its own top gap so it can vanish on
        // devices without a sensor without leaving a double gap.
        //
        // On a phone the settings root already shows the compact skin of this
        // very switch, and the auto-lock row beside it.
        if (BiometricUnlockService.platformSupported && !phone)
          const BiometricUnlockTile(),
        if (!phone) ...[
          const SettingsGap(),
          const SettingsGroup(label: 'Session', children: [AutoLockRow()]),
        ],
        const SettingsGap(),
        // Verifying a paper backup needs no secret and applies to every wallet
        // type — including the hardware and air-gap ones the seed tools below
        // can never touch.
        if (walletId != null) ...[
          BackupVerifyCard(walletId: walletId),
          const SettingsGap(),
        ],
        // Seed tools — software wallets only; HW/air-gap keep keys off-device.
        if (walletId != null && _hasSeed) ...[
          SeedPhraseCard(walletId: walletId),
          const SettingsGap(),
        ],
        _passwordGroup,
        const SettingsGap(),
        _storageGroup,
        if (walletId != null) ...[
          const SizedBox(height: AppSpacing.xxl),
          _DangerZone(onDelete: _deleteWallet),
        ],
      ],
    );
  }
}

// ── Appearance ────────────────────────────────────────────────────────────────

class _AppearanceSection extends StatefulWidget {
  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  final _bridge = walletBridge;
  WalletCustomization? _custom;
  final _nameCtrl = TextEditingController();
  bool _saving = false;
  String? _saveError;

  /// The active wallet's co-signers, when it has more than one key. Loaded
  /// here so Appearance can rename them — the same place the wallet's own
  /// name and colour are set.
  List<CosignerEntry> _cosigners = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadCosigners();
  }

  /// Keys plus labels. A singlesig wallet has none and the group stays away.
  Future<void> _loadCosigners() async {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return;
    try {
      final info = await _bridge.getWalletInfo(walletId);
      if (info.cosignerKeys.length < 2) return;
      final labels = await CosignerLabelStore.instance.load(walletId);
      if (!mounted) return;
      setState(() {
        _cosigners = resolveCosigners(
          cosignerKeys: info.cosignerKeys,
          labels: labels,
          localFingerprints: info.localFingerprints,
        );
        _requiredSigs = info.requiredSigs;
      });
    } catch (_) {
      // A wallet that will not open has bigger problems than its labels.
    }
  }

  int? _requiredSigs;

  Future<void> _editCosigner(CosignerEntry entry) async {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return;
    final edited = await showCosignerLabelEditor(
      context,
      label: entry.label,
      index: entry.index,
      subtitle: entry.fingerprint.isEmpty
          ? null
          : '${entry.fingerprint} · m/${entry.path}',
    );
    if (edited == null) return;
    await CosignerLabelStore.instance.saveOne(walletId, edited);
    await _loadCosigners();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return;
    final c = await WalletCustomizationStore.instance.load(walletId);
    if (mounted) {
      setState(() {
        _custom = c;
        _nameCtrl.text =
            c.nameOverride ?? context.read<AppState>().activeWalletName ?? '';
      });
    }
  }

  Future<void> _saveName() async {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null || _custom == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _bridge.renameWallet(walletId, name);
      final updated = _custom!.copyWith(nameOverride: name);
      await WalletCustomizationStore.instance.save(updated);
      if (mounted) {
        context.read<AppState>().setActiveWallet(
          walletId,
          name: name,
          type: context.read<AppState>().activeWalletType,
        );
        setState(() {
          _custom = updated;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Name saved'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = e.toString();
        });
      }
    }
  }

  Future<void> _saveColor(Color color) async {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null || _custom == null) return;
    final updated = _custom!.copyWith(accentColor: color.toARGB32());
    await WalletCustomizationStore.instance.save(updated);
    if (mounted) {
      // Re-tint the whole app immediately.
      context.read<AppState>().setAccent(color);
      setState(() => _custom = updated);
    }
  }

  /// Renaming the wallet's co-signers.
  ///
  /// Lives beside the wallet's own name and colour because it is the same
  /// kind of setting: local, cosmetic, and changeable at any time. The keys
  /// themselves are on Wallet info, where they cannot be edited by accident.
  Widget get _cosignerLabelsGroup {
    final s = AppScheme.of(context);
    return SettingsGroup(
      label: 'Cosigner labels',
      note: _requiredSigs == null
          ? 'Name each key of this shared wallet. Names are kept on this '
                'device only.'
          : 'Name each key of this $_requiredSigs-of-${_cosigners.length} '
                'wallet. Names are kept on this device only.',
      children: [
        for (final entry in _cosigners)
          SettingsRow(
            icon: entry.label.icon,
            title: entry.name,
            subtitle: entry.isLocal
                ? '${entry.fingerprint} · this device'
                : entry.fingerprint,
            mono: true,
            trailing: Icon(
              Icons.edit_outlined,
              size: AppSpacing.iconSmall,
              color: s.inkSecondary,
            ),
            onTap: () => _editCosigner(entry),
          ),
      ],
    );
  }

  /// The wallet's display name and its accent colour.
  Widget get _walletGroup {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final saveButton = SecondaryButton(
      label: _saving ? 'Saving…' : 'Save',
      onPressed: _saving ? null : _saveName,
      isFullWidth: phone,
    );
    final field = TextField(
      controller: _nameCtrl,
      decoration: const InputDecoration(hintText: 'Wallet name'),
      onSubmitted: (_) {
        if (!_saving) _saveName();
      },
    );
    return SettingsGroup(
      label: 'Active wallet',
      blocks: true,
      note:
          'The accent tints this wallet everywhere: its mark in the wallet '
          'list, the sidebar, and every accent inside it.',
      children: [
        SettingsBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Display name',
                style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Phone: a 54 dp Save beside the field leaves the name about
              // 190 dp of a 347 dp line, so the two stack instead.
              if (phone) ...[
                field,
                const SizedBox(height: AppSpacing.md),
                saveButton,
              ] else
                Row(
                  children: [
                    Expanded(child: field),
                    const SizedBox(width: AppSpacing.sm),
                    saveButton,
                  ],
                ),
              if (_saveError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _saveError!,
                  style: AppTypography.caption.copyWith(color: s.danger),
                ),
              ],
            ],
          ),
        ),
        SettingsBlock(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Accent color',
                style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: phone ? 0 : AppSpacing.sm,
                runSpacing: phone ? 0 : AppSpacing.sm,
                children: [
                  for (
                    var i = 0;
                    i < WalletCustomizationStore.palette.length;
                    i++
                  )
                    _Swatch(
                      color: WalletCustomizationStore.palette[i],
                      index: i,
                      // No colour picked yet is the brand crimson, the
                      // first swatch: it is the one in use, and it says so.
                      selected:
                          (_custom!.accentColor ??
                              AppColors.accentDefault.toARGB32()) ==
                          WalletCustomizationStore.palette[i].toARGB32(),
                      onTap: () =>
                          _saveColor(WalletCustomizationStore.palette[i]),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasWallet =
        context.watch<AppState>().activeWalletId != null && _custom != null;
    return Consumer<AppState>(
      builder: (context, state, _) {
        final phone = AppLayout.isPhone(context);
        final themeTrack = SegmentedSwitch<ThemeMode>(
          expand: phone,
          options: const [
            SegOption(value: ThemeMode.dark, label: 'Dark'),
            SegOption(value: ThemeMode.light, label: 'Light'),
            SegOption(value: ThemeMode.system, label: 'System'),
          ],
          selected: state.themeMode,
          onChanged: state.setThemeMode,
        );
        final unitTrack = SegmentedSwitch<bool>(
          options: const [
            SegOption(value: false, label: 'BTC'),
            SegOption(value: true, label: 'sats'),
          ],
          selected: state.useSats,
          onChanged: (v) => state.setBitcoinUnit(v ? 'sat' : 'btc'),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsGroup(
              label: 'Theme',
              blocks: phone,
              children: [
                // Phone: the track takes the card's width in a block of its
                // own; three segments beside a row title do not fit 347 dp.
                if (phone)
                  SettingsBlock(child: themeTrack)
                else
                  SettingsRow(
                    icon: Icons.contrast_outlined,
                    title: 'Theme',
                    subtitle: 'System follows the operating system',
                    trailing: themeTrack,
                  ),
              ],
            ),
            const SettingsGap(),
            SettingsGroup(
              label: 'Currency and units',
              note: 'How balances and value estimates are displayed',
              children: [
                SettingsRow(
                  icon: Icons.payments_outlined,
                  title: 'Fiat currency',
                  subtitle: 'For value estimates',
                  trailing: _CurrencyMenu(
                    value: state.fiatCurrency,
                    onChanged: state.setFiatCurrency,
                  ),
                ),
                SettingsRow(
                  icon: Icons.currency_bitcoin_outlined,
                  title: 'Bitcoin unit',
                  subtitle: state.useSats
                      ? '1 BTC = 100,000,000 sats'
                      : 'Amounts in BTC',
                  trailing: unitTrack,
                ),
              ],
            ),
            if (hasWallet) ...[const SettingsGap(), _walletGroup],
            if (_cosigners.length > 1) ...[
              const SettingsGap(),
              _cosignerLabelsGroup,
            ],
          ],
        );
      },
    );
  }
}

/// The fiat currency, as the row's quiet value with a menu behind it.
class _CurrencyMenu extends StatelessWidget {
  const _CurrencyMenu({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        dropdownColor: s.panel,
        icon: Icon(
          Icons.expand_more_outlined,
          size: AppSpacing.icon,
          color: s.inkSecondary,
        ),
        style: AppTypography.body.copyWith(color: s.ink),
        items: [
          for (final e in PriceService.currencySymbols.entries)
            DropdownMenuItem(
              value: e.key,
              child: Text('${e.key}  (${e.value.trim()})'),
            ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

/// One accent swatch: 24 px of the colour; chosen, a 2 px ink ring with a
/// 2 px gap. The colour is the wallet's identity, so it is data, not chrome.
class _Swatch extends StatefulWidget {
  const _Swatch({
    required this.color,
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_Swatch> createState() => _SwatchState();
}

class _SwatchState extends State<_Swatch> {
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    // Touch keeps its 48 dp floor around the same 24 px mark.
    final cell = phone ? AppLayout.minTouchTarget : AppSpacing.xxl;
    final ring = widget.selected
        ? s.ink
        : _focus
        ? s.focus
        : Colors.transparent;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: 'Accent color ${widget.index + 1}',
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
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
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: cell,
            height: cell,
            child: Center(
              child: Container(
                width: AppSpacing.xxl,
                height: AppSpacing.xxl,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 2),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── About ─────────────────────────────────────────────────────────────────────

class _AboutSection extends StatefulWidget {
  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  /// wallet-ffi crate version reported by the engine; null while loading.
  String? _engineVersion;

  /// The version handshake failed — the dylib did not answer.
  bool _engineUnreachable = false;

  @override
  void initState() {
    super.initState();
    _loadEngineVersion();
  }

  Future<void> _loadEngineVersion() async {
    try {
      final v = await walletBridge.getVersion();
      if (mounted) setState(() => _engineVersion = v);
    } catch (_) {
      if (mounted) setState(() => _engineUnreachable = true);
    }
  }

  Future<void> _openSource() async {
    final uri = Uri.parse('https://github.com/0xB4LdW1n/TemplarWallet');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final engine = _engineVersion;
    return SettingsGroup(
      label: 'Templar Wallet',
      note: _engineUnreachable
          ? 'Engine unreachable — the native wallet library did not respond. '
                'Wallet operations will not work.'
          : null,
      noteColor: s.danger,
      children: [
        const SettingsRow(
          icon: Icons.info_outline,
          title: 'Version',
          subtitle: 'Test networks only',
          trailing: SettingsValue('v$kAppVersion', mono: true),
        ),
        SettingsRow(
          icon: Icons.memory_outlined,
          title: 'Engine (wallet-ffi)',
          subtitle: _engineUnreachable
              ? 'Unreachable'
              : 'Native wallet library',
          dot: _engineUnreachable ? s.danger : null,
          trailing: _engineUnreachable
              ? null
              : SettingsValue(engine != null ? 'v$engine' : '…', mono: true),
        ),
        SettingsRow(
          icon: Icons.code_outlined,
          title: 'Source code',
          subtitle: 'github.com/0xB4LdW1n/TemplarWallet',
          mono: true,
          trailing: Icon(
            Icons.open_in_new_outlined,
            size: AppSpacing.iconSmall,
            color: s.inkFaint,
          ),
          onTap: _openSource,
        ),
        SettingsRow(
          icon: Icons.description_outlined,
          title: 'Open-source licenses',
          subtitle: 'The packages this app is built from',
          chevron: true,
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Templar Wallet',
            applicationVersion: 'v$kAppVersion',
          ),
        ),
      ],
    );
  }
}

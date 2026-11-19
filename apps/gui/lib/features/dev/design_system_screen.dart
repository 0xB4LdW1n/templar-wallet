import 'package:flutter/material.dart';

import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/choice_list.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/expander.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/seal_mark.dart';
import '../../shared/widgets/segmented_switch.dart';
import '../../shared/widgets/step_header.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The kit gallery (route `/dev/design`): every shared widget on the live
/// tokens, through the same constructors the screens use. If something
/// looks wrong here it looks wrong everywhere.
class DesignSystemScreen extends StatefulWidget {
  const DesignSystemScreen({super.key});

  @override
  State<DesignSystemScreen> createState() => _DesignSystemScreenState();
}

class _DesignSystemScreenState extends State<DesignSystemScreen> {
  String _segment = 'bitcoin';
  String _chip = '1 day';
  int _option = 0;
  String _listChoice = 'single';
  final _label = TextEditingController(text: 'Savings');
  final _amount = TextEditingController(text: '0.5');
  final _password = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    _password.dispose();
    super.dispose();
  }

  static const _descriptor =
      'wpkh([deadbeef/84h/1h/0h]tpubDC7KMhGhFE2MhAJXrWMxumRnpFDqgtQQiQSFLGCaAk5CW8BQBuNr7PKRqNGV1ZB6qKP3zERkHV7DGUzPMDQc2y4kF7K8UrHeRfFXWkHPPjE/0/*)';

  void _openDialog() {
    showAppDialog<void>(
      context,
      builder: (ctx) => AppDialog(
        title: const Text('Forget this wallet'),
        content: const Text(
          'The wallet is removed from this device. Its coins stay on chain '
          'and come back with the recovery phrase.',
        ),
        actions: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          DangerButton(
            label: 'Forget',
            icon: Icons.delete_outline,
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final pad = AppSpacing.pagePadding(context);
    return Scaffold(
      backgroundColor: s.canvas,
      body: PageBackground(
        child: ListView(
          padding: EdgeInsets.all(pad),
          children: [
            const PageHeader(
              title: 'Design system',
              subtitle: 'Every shared widget on the live tokens',
            ),
            _section('Surfaces', [_surfaces(s)]),
            _section('Ink', [_inks(s)]),
            _section('Type scale', [_typeScale(s)]),
            _section('Buttons', _buttons()),
            _section('Fields', [_fields()]),
            _section('Segmented control', [
              SegmentedSwitch<String>(
                options: [
                  const SegOption(
                    value: 'bitcoin',
                    label: 'Bitcoin',
                    logo: AssetLogo(
                      ticker: 'BTC',
                      size: SegmentedSwitch.logoSize,
                    ),
                  ),
                  const SegOption(
                    value: 'liquid',
                    label: 'Liquid',
                    logo: AssetLogo(
                      ticker: 'LIQUID',
                      size: SegmentedSwitch.logoSize,
                    ),
                  ),
                  const SegOption(
                    value: 'regtest',
                    label: 'Regtest',
                    enabled: false,
                    tooltip: 'Not on this wallet',
                  ),
                ],
                selected: _segment,
                onChanged: (v) => setState(() => _segment = v),
              ),
            ]),
            _section('Chips', [
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final p in const ['1 day', '1 week', '1 month'])
                    ChoiceTile(
                      label: p,
                      selected: _chip == p,
                      onSelected: () => setState(() => _chip = p),
                    ),
                  const ChoiceTile(
                    label: 'All time',
                    selected: false,
                    tooltip: 'Not enough history',
                  ),
                ],
              ),
            ]),
            _section('Option cards', [
              SelectableOptionCard(
                title: 'Single key',
                description: 'One key signs every spend',
                icon: Icons.key_outlined,
                isSelected: _option == 0,
                onTap: () => setState(() => _option = 0),
              ),
              const SizedBox(height: AppSpacing.md),
              SelectableOptionCard(
                title: 'Multisig',
                description: 'Several keys, a threshold of them signs',
                icon: Icons.groups_outlined,
                badge: 'Coming soon',
                isSelected: _option == 1,
                onTap: () => setState(() => _option = 1),
              ),
              const SizedBox(height: AppSpacing.lg),
              ChoiceList<String>(
                options: const [
                  ChoiceListOption(
                    value: 'single',
                    label: 'This device',
                    icon: Icons.computer_outlined,
                    note: 'signs here',
                  ),
                  ChoiceListOption(
                    value: 'hw',
                    label: 'Hardware device',
                    icon: Icons.usb_outlined,
                  ),
                  ChoiceListOption(
                    value: 'airgap',
                    label: 'Air-gapped signer',
                    icon: Icons.qr_code_2_outlined,
                    enabled: false,
                    disabledReason: 'Needs a camera',
                  ),
                ],
                selected: _listChoice,
                onChanged: (v) => setState(() => _listChoice = v),
              ),
            ]),
            _section('Tags and status', [
              const Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(label: 'Synced', variant: BadgeVariant.success),
                  StatusBadge(label: 'Pending', variant: BadgeVariant.warning),
                  StatusBadge(label: 'Failed', variant: BadgeVariant.danger),
                  StatusBadge(label: 'Watch-only'),
                  AssetBadge(ticker: 'btc'),
                  AssetBadge(ticker: 'lbtc'),
                  TestnetBadge(),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  TagChip(label: 'Change', color: s.inkSecondary),
                  TagChip(label: 'Liquid', color: s.liquid),
                  TagChip(label: 'Stale data', color: s.warning),
                  AssetChip(
                    ticker: 'BTC',
                    amount: '0.01734567',
                    isSelected: true,
                    onTap: () {},
                  ),
                  AssetChip(ticker: 'USDT', amount: '100.00', onTap: () {}),
                ],
              ),
            ]),
            _section('Banners', [
              const InfoBanner(
                message: 'Fees on testnet are paid in test coins',
              ),
              const SizedBox(height: AppSpacing.md),
              WarningBanner(
                title: 'Backup not confirmed',
                message:
                    'Write the recovery phrase down before you receive coins.',
                action: SecondaryButton(label: 'Back up now', onPressed: () {}),
              ),
              const SizedBox(height: AppSpacing.md),
              const DangerBanner(
                message: 'Broadcast failed: min relay fee not met',
              ),
            ]),
            _section('Cards', [
              FormCard(
                title: 'Form card',
                subtitle: 'One quiet line under the title',
                child: Text(
                  'Content sits 16 under the title.',
                  style: AppTypography.body.copyWith(color: s.inkSecondary),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const SummaryCard(
                title: 'Summary card',
                rows: [
                  (label: 'Amount', value: '0.01734567 BTC', isMono: false),
                  (label: 'Fee rate', value: '2 sat/vB', isMono: false),
                  (label: 'Fingerprint', value: 'deadbeef', isMono: true),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              const ExpanderCardDemo(),
              const SizedBox(height: AppSpacing.lg),
              HeroPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total balance',
                      style: AppTypography.eyebrow.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '1,734,567 sats',
                      style: AppTypography.balanceHeroOf(
                        context,
                      ).copyWith(color: s.ink),
                    ),
                  ],
                ),
              ),
            ]),
            _section('List card', [
              ListCard(
                children: [
                  ListRow(
                    icon: Icons.currency_bitcoin_outlined,
                    tint: s.bitcoin,
                    title: 'Bitcoin',
                    subtitle: 'Testnet',
                    trailing: const ListAmount(
                      value: '0.01734567',
                      unit: 'BTC',
                    ),
                  ),
                  ListRow(
                    icon: Icons.water_drop_outlined,
                    tint: s.liquid,
                    title: 'Liquid',
                    subtitle: 'Testnet',
                    trailing: const ListAmount(
                      value: '0.00500000',
                      unit: 'LBTC',
                    ),
                  ),
                  ListRow(
                    icon: Icons.settings_outlined,
                    tint: s.inkSecondary,
                    title: 'Settings',
                    subtitle: 'Security, network, appearance',
                    chevron: true,
                    onTap: () {},
                  ),
                ],
              ),
            ]),
            _section('Key / value rows', [
              const DataWell(
                child: Column(
                  children: [
                    KvRow(label: 'Outpoint', value: 'a1b2c3d4…e5f6:0'),
                    KvRow(label: 'Address', value: 'tb1qw508d6qejxtdg4y5r3zar'),
                    KvRow(label: 'Confirmations', value: '12'),
                  ],
                ),
              ),
            ]),
            _section('Code box', const [
              CodeBox(label: 'Descriptor', value: _descriptor),
              SizedBox(height: AppSpacing.lg),
              CopyRow(label: 'Master fingerprint', value: 'deadbeef'),
              CopyRow(label: 'Wallet name', value: 'Primary', mono: false),
            ]),
            _section('Step header', [
              StepHeader(
                currentStep: 2,
                totalSteps: 6,
                title: 'Who signs for this wallet',
                onBack: () {},
              ),
            ]),
            _section('Dialog', [
              Align(
                alignment: Alignment.centerLeft,
                child: SecondaryButton(
                  label: 'Open a dialog',
                  icon: Icons.open_in_new_outlined,
                  onPressed: _openDialog,
                ),
              ),
            ]),
            _section('Seal', [
              Row(
                children: [
                  for (final stamped in const [true, true, false]) ...[
                    SealMark(stamped: stamped, size: 32),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '2 of 3 signatures',
                    style: AppTypography.body.copyWith(color: s.inkSecondary),
                  ),
                ],
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// A labelled block: `eyebrow` name, 8 under it, 32 to the next block.
  Widget _section(String name, List<Widget> children) {
    final s = AppScheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.contentMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _surfaces(AppScheme s) {
    final steps = <(String, Color)>[
      ('chrome', s.chrome),
      ('canvas', s.canvas),
      ('panel', s.panel),
      ('panelInset', s.panelInset),
    ];
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final (name, color) in steps)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 120,
                height: 72,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: s.edge),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                name,
                style: AppTypography.monoSmall.copyWith(color: s.inkSecondary),
              ),
              Text(
                _hex(color),
                style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
              ),
            ],
          ),
      ],
    );
  }

  Widget _inks(AppScheme s) {
    final inks = <(String, Color, String)>[
      ('ink', s.ink, 'What is read: titles, figures, values'),
      ('inkSecondary', s.inkSecondary, 'What supports it: body, keys, icons'),
      ('inkFaint', s.inkFaint, 'Meta only: captions, units, timestamps'),
    ];
    return FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (name, color, use) in inks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      name,
                      style: AppTypography.monoSmall.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      use,
                      style: AppTypography.body.copyWith(color: color),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _typeScale(AppScheme s) {
    final styles = <(String, TextStyle)>[
      ('balanceHero', AppTypography.balanceHero),
      ('displayTitle', AppTypography.displayTitle),
      ('pageTitle', AppTypography.pageTitle),
      ('balanceLarge', AppTypography.balanceLarge),
      ('balanceMedium', AppTypography.balanceMedium),
      ('numericLarge', AppTypography.numericLarge),
      ('galleryTitle', AppTypography.galleryTitle),
      ('sectionTitle', AppTypography.sectionTitle),
      ('bodyLarge', AppTypography.bodyLarge),
      ('body', AppTypography.body),
      ('numeric', AppTypography.numeric),
      ('button', AppTypography.button),
      ('navItem', AppTypography.navItem),
      ('caption', AppTypography.caption),
      ('bodySmall', AppTypography.bodySmall),
      ('numericSmall', AppTypography.numericSmall),
      ('label', AppTypography.label),
      ('eyebrow', AppTypography.eyebrow),
      ('monoLarge', AppTypography.monoLarge),
      ('mono', AppTypography.mono),
      ('monoSmall', AppTypography.monoSmall),
    ];
    final phone = AppLayout.isPhone(context);
    return FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (name, style) in styles)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: phone ? 112 : 160,
                    child: Text(
                      '$name ${style.fontSize?.round()}',
                      style: AppTypography.monoSmall.copyWith(
                        color: s.inkFaint,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      name.startsWith('balance') || name.startsWith('numeric')
                          ? '1,734,567'
                          : name.startsWith('mono')
                          ? 'deadbeef/84h/1h/0h'
                          : 'Wallet info',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style.copyWith(color: s.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buttons() {
    Widget row(List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: children,
      ),
    );
    return [
      row([
        PrimaryButton(label: 'Send', onPressed: () {}),
        SecondaryButton(label: 'Receive', onPressed: () {}),
        GhostButton(label: 'Cancel', onPressed: () {}),
        DangerButton(
          label: 'Delete',
          icon: Icons.delete_outline,
          onPressed: () {},
        ),
      ]),
      row(const [
        PrimaryButton(label: 'Send'),
        SecondaryButton(label: 'Receive'),
        GhostButton(label: 'Cancel'),
        DangerButton(label: 'Delete', icon: Icons.delete_outline),
      ]),
      row(const [
        PrimaryButton(label: 'Signing', isLoading: true),
        SecondaryButton(label: 'Reading', isLoading: true),
      ]),
      row([
        PrimaryButton(
          label: 'Send',
          icon: Icons.arrow_upward_outlined,
          onPressed: () {},
        ),
        SecondaryButton(
          label: 'Receive',
          icon: Icons.arrow_downward_outlined,
          onPressed: () {},
        ),
        GhostButton(label: 'Copy', icon: Icons.copy_outlined, onPressed: () {}),
      ]),
    ];
  }

  Widget _fields() {
    final s = AppScheme.of(context);
    Widget labelled(String label, Widget field) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          field,
        ],
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSpacing.formMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          labelled('Label', TextField(controller: _label)),
          labelled(
            'Note',
            const TextField(decoration: InputDecoration(hintText: 'Optional')),
          ),
          labelled(
            'Amount',
            TextField(
              controller: _amount,
              decoration: const InputDecoration(
                errorText: 'More than the spendable balance',
              ),
            ),
          ),
          PasswordField(controller: _password),
        ],
      ),
    );
  }

  static String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}

/// An [ExpanderCard] in the gallery, open so its body is on the page.
class ExpanderCardDemo extends StatelessWidget {
  const ExpanderCardDemo({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return ExpanderCard(
      title: 'How it works',
      subtitle: 'Expander card',
      trailing: const StatusBadge(label: '3'),
      initiallyExpanded: true,
      child: Text(
        'The body folds away under the header. Its height follows the '
        'content; the content fades in.',
        style: AppTypography.body.copyWith(color: s.inkSecondary),
      ),
    );
  }
}

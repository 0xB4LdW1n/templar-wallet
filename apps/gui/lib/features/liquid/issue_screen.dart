import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../features/liquid/models/issue_result.dart';
import '../../services/issued_asset_store.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/step_header.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'form_parts.dart';

class IssueScreen extends StatefulWidget {
  const IssueScreen({super.key});

  @override
  State<IssueScreen> createState() => _IssueScreenState();
}

class _IssueScreenState extends State<IssueScreen> {
  final _bridge = walletBridge;

  int _step = 1;
  static const int _totalSteps = 4;

  final _nameController = TextEditingController();
  final _tickerController = TextEditingController();
  final _precisionController = TextEditingController(text: '8');
  final _domainController = TextEditingController();
  final _supplyController = TextEditingController();
  bool _createReissuanceToken = true;

  bool _issuing = false;
  String? _error;
  IssueResult? _result;

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _tickerController,
      _precisionController,
      _domainController,
      _supplyController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // Mirrors lwk_wollet's Contract validation rules — invalid metadata is
  // permanently committed into the asset id, so it must never reach signing.
  static final _asciiNameRe = RegExp(r'^[\x00-\x7F]{1,255}$');
  static final _tickerRe = RegExp(r'^[a-zA-Z0-9.\-]{3,24}$');
  static final _domainLabelRe = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');
  static final _tldRe = RegExp(r'^[a-z]{2,}$');

  /// Validates step 1 fields. Returns the first error, or null.
  /// Normalizes the domain controller (scheme/path stripped, lowercased).
  String? _validateMetadata() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return 'Asset name is required.';
    if (!_asciiNameRe.hasMatch(name)) {
      return 'Asset name must be 1–255 ASCII characters.';
    }
    final ticker = _tickerController.text.trim();
    if (ticker.isEmpty) return 'Ticker is required.';
    if (!_tickerRe.hasMatch(ticker)) {
      return 'Ticker must be 3–24 characters using letters, digits, "." or "-".';
    }
    final precisionText = _precisionController.text.trim();
    if (precisionText.isEmpty) return 'Precision is required.';
    final precision = int.tryParse(precisionText);
    if (precision == null || precision < 0 || precision > 8) {
      return 'Precision must be a whole number between 0 and 8.';
    }
    final domain = _domainController.text
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .trim();
    _domainController.text = domain;
    if (domain.isEmpty) return 'Domain is required (e.g. username.github.io).';
    if (domain.length > 255) return 'Domain must be at most 255 characters.';
    final labels = domain.split('.');
    if (labels.length < 2 || labels.any((l) => !_domainLabelRe.hasMatch(l))) {
      return 'Enter a bare domain like username.github.io — lowercase letters, '
          'digits, and inner hyphens only, with at least two labels.';
    }
    if (!_tldRe.hasMatch(labels.last)) {
      return 'The top-level domain must be alphabetic and at least 2 characters.';
    }
    return null;
  }

  /// Validates step 2 fields. Returns the first error, or null.
  String? _validateSupply() {
    final supplyText = _supplyController.text.trim();
    if (supplyText.isEmpty) return 'Initial supply is required.';
    final supply = int.tryParse(supplyText);
    if (supply == null || supply <= 0) {
      return 'Initial supply must be a whole number greater than 0.';
    }
    return null;
  }

  Future<void> _onSignAndIssue() async {
    final validationError = _validateMetadata() ?? _validateSupply();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    final name = _nameController.text.trim();
    final ticker = _tickerController.text.trim();
    final domain = _domainController.text.trim();
    final supply = int.parse(_supplyController.text.trim());
    final precision = int.parse(_precisionController.text.trim());

    setState(() {
      _error = null;
      _issuing = true;
    });

    try {
      final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
      final result = await _bridge.issueAsset(
        walletId: walletId,
        name: name,
        ticker: ticker,
        precision: precision,
        domain: domain,
        amountSats: supply,
        reissuanceTokens: _createReissuanceToken ? 1 : 0,
      );
      // Persist the full contract data locally (scoped to wallet) so the
      // registry submission can be rebuilt and retried later — e.g. from
      // Asset Operations — if the best-effort registration failed (offline).
      IssuedAssetStore.instance.saveIssuedAsset(
        walletId,
        IssuedAssetEntry(
          assetId: result.assetId,
          name: name,
          ticker: ticker,
          tokenId: result.tokenId,
          precision: precision,
          domain: domain,
          registered: result.registryRegistered,
        ),
      );
      if (mounted) {
        setState(() {
          _result = result;
          _issuing = false;
          _step = 4;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _issuing = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _onReregister() async {
    final result = _result;
    if (result == null) return;
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    try {
      final ok = await _bridge.reregisterAsset(
        walletId: walletId,
        assetId: result.assetId,
        name: _nameController.text.trim(),
        ticker: _tickerController.text.trim(),
        precision: int.tryParse(_precisionController.text.trim()) ?? 8,
        domain: _domainController.text.trim(),
      );
      if (ok) {
        await IssuedAssetStore.instance.markRegistered(
          walletId,
          result.assetId,
        );
      }
      if (mounted) {
        if (ok) {
          // Flip the result banner from "proof required" to registered.
          setState(() {
            _result = IssueResult(
              assetId: result.assetId,
              tokenId: result.tokenId,
              txid: result.txid,
              registryRegistered: true,
              proofUrl: result.proofUrl,
              proofContent: result.proofContent,
            );
          });
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Asset registered'
                  : 'Registration failed — ensure the domain proof file is live',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    return Scaffold(
      body: PageBackground.flat(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.formMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step < 4)
                    StepHeader(
                      currentStep: _step,
                      totalSteps: _totalSteps,
                      title: _stepTitle,
                      subtitle: _stepSubtitle,
                      onBack: _step > 1 ? () => setState(() => _step--) : null,
                      onCancel: () => context.go(AppRoutes.liquid),
                    )
                  else
                    const PageHeader(
                      title: 'Asset issued',
                      subtitle: 'Broadcast on-chain',
                    ),
                  SizedBox(height: phone ? AppSpacing.lg : AppSpacing.xl),
                  Expanded(child: _stepBody),
                  if (_step < 4) ...[
                    SizedBox(height: phone ? AppSpacing.lg : AppSpacing.xl),
                    _buildNavButtons(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavButtons() {
    final last = _step == 3;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (_step > 1) ...[
          GhostButton(label: 'Back', onPressed: () => setState(() => _step--)),
          const SizedBox(width: AppSpacing.sm),
        ],
        if (last)
          PrimaryButton(
            label: _issuing ? 'Broadcasting…' : 'Issue asset',
            isLoading: _issuing,
            onPressed: _onSignAndIssue,
          )
        else
          PrimaryButton(label: 'Continue', onPressed: _onNextStep),
      ],
    );
  }

  void _onNextStep() {
    final validationError = switch (_step) {
      1 => _validateMetadata(),
      2 => _validateSupply(),
      _ => null,
    };
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _error = null;
      _step++;
    });
  }

  String get _stepTitle => switch (_step) {
    1 => 'Define asset',
    2 => 'Initial supply',
    3 => 'Review and sign',
    _ => 'Asset issued',
  };

  String get _stepSubtitle => switch (_step) {
    1 => 'Asset metadata is permanent and cannot be changed after issuance',
    2 => 'Set the initial token supply delivered to this wallet',
    3 => 'Review all details before broadcasting the issuance transaction',
    _ => 'Asset has been issued on-chain',
  };

  Widget get _stepBody => switch (_step) {
    1 => _Step1(
      name: _nameController,
      ticker: _tickerController,
      precision: _precisionController,
      domain: _domainController,
      error: _error,
    ),
    2 => _Step2(
      supply: _supplyController,
      createToken: _createReissuanceToken,
      onToggleToken: (v) => setState(() => _createReissuanceToken = v),
      error: _error,
    ),
    3 => _Step3Review(
      name: _nameController.text,
      ticker: _tickerController.text,
      precision: _precisionController.text,
      domain: _domainController.text,
      supply: _supplyController.text,
      hasReissuanceToken: _createReissuanceToken,
      error: _error,
    ),
    _ => _Step4Result(
      result: _result!,
      onReregister: _onReregister,
      onDone: () => context.go(AppRoutes.liquid),
    ),
  };
}

// ── Step 1 ────────────────────────────────────────────────────────────────────

class _Step1 extends StatelessWidget {
  const _Step1({
    required this.name,
    required this.ticker,
    required this.precision,
    required this.domain,
    this.error,
  });
  final TextEditingController name;
  final TextEditingController ticker;
  final TextEditingController precision;
  final TextEditingController domain;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        FieldBlock(
          label: 'Token name',
          child: TextField(controller: name),
        ),
        const SizedBox(height: AppSpacing.lg),
        FieldBlock(
          label: 'Ticker',
          help: '3–24 letters, digits, "." or "-"',
          child: TextField(
            controller: ticker,
            decoration: const InputDecoration(hintText: 'MYTKN'),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FieldBlock(
          label: 'Precision',
          help: 'Decimal places, 0–8',
          child: TextField(
            controller: precision,
            style: AppTypography.numeric,
            decoration: const InputDecoration(hintText: '8'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FieldBlock(
          label: 'Domain',
          help: 'Hostname only — no https://, no trailing slash, no path',
          child: TextField(
            controller: domain,
            // The registry rejects uppercase domains — normalize as typed.
            inputFormatters: [
              TextInputFormatter.withFunction(
                (oldValue, newValue) =>
                    newValue.copyWith(text: newValue.text.toLowerCase()),
              ),
            ],
            decoration: const InputDecoration(hintText: 'username.github.io'),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _InlineError(message: error!),
        ],
      ],
    );
  }
}

// ── Step 2 ────────────────────────────────────────────────────────────────────

class _Step2 extends StatelessWidget {
  const _Step2({
    required this.supply,
    required this.createToken,
    required this.onToggleToken,
    this.error,
  });
  final TextEditingController supply;
  final bool createToken;
  final void Function(bool) onToggleToken;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return ListView(
      children: [
        FieldBlock(
          label: 'Initial supply',
          help: 'In base units, delivered to this wallet',
          child: TextField(
            controller: supply,
            style: AppTypography.numeric,
            decoration: const InputDecoration(hintText: '0'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SectionCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create reissuance token',
                      style: AppTypography.body.copyWith(color: s.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Allows minting more supply in the future. Losing this '
                      'token means no future reissuance.',
                      style: AppTypography.caption.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              ListSwitch(
                value: createToken,
                onChanged: onToggleToken,
                semanticLabel: 'Create reissuance token',
              ),
            ],
          ),
        ),
        if (!createToken) ...[
          const SizedBox(height: AppSpacing.md),
          const WarningBanner(
            message:
                'Without a reissuance token, the total supply is permanently '
                'fixed at issuance.',
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _InlineError(message: error!),
        ],
      ],
    );
  }
}

// ── Step 3 ────────────────────────────────────────────────────────────────────

class _Step3Review extends StatelessWidget {
  const _Step3Review({
    required this.name,
    required this.ticker,
    required this.precision,
    required this.domain,
    required this.supply,
    required this.hasReissuanceToken,
    this.error,
  });

  final String name;
  final String ticker;
  final String precision;
  final String domain;
  final String supply;
  final bool hasReissuanceToken;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        // Issuing creates supply; nothing is lost, so this is a warning, not
        // the danger voice that is kept for burning and deleting.
        const WarningBanner(
          title: 'Final review',
          message:
              'Once signed and broadcast, asset metadata cannot be changed. '
              'Check every detail.',
        ),
        const SizedBox(height: AppSpacing.xl),
        SummaryCard(
          title: 'Asset details',
          rows: [
            (label: 'Operation', value: 'Issue', isMono: false),
            (label: 'Name', value: name.isEmpty ? '—' : name, isMono: false),
            (
              label: 'Ticker',
              value: ticker.isEmpty ? '—' : ticker,
              isMono: false,
            ),
            (label: 'Precision', value: precision, isMono: false),
            (
              label: 'Domain',
              value: domain.isEmpty ? '—' : domain,
              isMono: false,
            ),
            (
              label: 'Initial supply',
              value: supply.isEmpty ? '—' : supply,
              isMono: false,
            ),
            (
              label: 'Reissuance token',
              value: hasReissuanceToken ? 'Yes' : 'No',
              isMono: false,
            ),
            (label: 'Contract hash', value: 'Computed on sign', isMono: false),
            (
              label: 'Asset ID',
              value: 'Derived after broadcast',
              isMono: false,
            ),
            // The engine sets the fee when it builds the transaction; a
            // figure here would be one it never gave us.
            (label: 'Network fee', value: 'Set on sign', isMono: false),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _InlineError(message: error!),
        ],
      ],
    );
  }
}

// ── Inline validation error ───────────────────────────────────────────────────

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => DangerBanner(message: message);
}

// ── Step 4: Result ────────────────────────────────────────────────────────────

class _Step4Result extends StatelessWidget {
  const _Step4Result({
    required this.result,
    required this.onReregister,
    required this.onDone,
  });
  final IssueResult result;
  final VoidCallback onReregister;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return ListView(
      children: [
        if (result.registryRegistered)
          const InfoBanner(
            message: 'Asset registered in the Liquid testnet explorer',
          )
        else
          const WarningBanner(
            title: 'Domain proof required',
            message:
                'Explorer registration pending. Create the file below on your '
                'domain to complete registration.',
          ),
        const SizedBox(height: AppSpacing.xl),
        CodeBox(label: 'Asset ID', value: result.assetId, maxLines: 2),
        if (result.tokenId != null) ...[
          const SizedBox(height: AppSpacing.lg),
          CodeBox(
            label: 'Reissuance token ID',
            value: result.tokenId!,
            maxLines: 2,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        CodeBox(label: 'TxID', value: result.txid, maxLines: 2),
        if (!result.registryRegistered && result.proofUrl.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          SectionCard(
            title: 'Domain proof',
            subtitle:
                'Create this file on your domain to register with the Liquid '
                'explorer',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CodeBox(label: 'File URL', value: result.proofUrl),
                const SizedBox(height: AppSpacing.lg),
                CodeBox(
                  label: 'File content (plain text, no extension)',
                  value: result.proofContent,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'GitHub Pages: add the file at '
                  '.well-known/liquid-asset-proof-<asset_id> in your '
                  '<username>.github.io repo. The registry verifies it '
                  'automatically within ~5 minutes of the tx confirming.',
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
                const SizedBox(height: AppSpacing.lg),
                SecondaryButton(
                  label: 'Register again',
                  icon: Icons.refresh,
                  onPressed: onReregister,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(label: 'Done', isFullWidth: true, onPressed: onDone),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

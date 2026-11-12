/// Central human copy for Templar Lend surfaces.
///
/// English remains the app default. Italian is complete and ready for the
/// app-wide locale switch; keeping both here prevents protocol vocabulary
/// from drifting between overview, detail and signing review.
class ProtocolCopy {
  const ProtocolCopy._(this.languageCode);

  static const english = ProtocolCopy._('en');
  static const italian = ProtocolCopy._('it');

  final String languageCode;
  bool get _it => languageCode == 'it';

  String action(String raw) {
    final value = raw.trim();
    final labels = _it ? _actionsIt : _actionsEn;
    return labels[value] ?? _humanize(value, italian: _it);
  }

  String role(String raw) => switch (raw.trim()) {
    'borrower' => _it ? 'Debitore' : 'Borrower',
    'lender' => _it ? 'Creditore' : 'Lender',
    final value => _humanize(value, italian: _it),
  };

  String state(String raw) => switch (raw.trim()) {
    'originating' => _it ? 'In apertura' : 'Opening',
    'active' => _it ? 'Attivo' : 'Active',
    'repaid' => _it ? 'Rimborsato' : 'Repaid',
    'defaulted' => _it ? 'In default' : 'Defaulted',
    'liquidated' => _it ? 'Liquidato' : 'Liquidated',
    final value => _humanize(value, italian: _it),
  };

  String primaryAction({
    required String state,
    String? pendingAction,
    String? nextKind,
    bool collateralReturnReady = false,
  }) {
    if (pendingAction != null && pendingAction.isNotEmpty) {
      return _it ? 'Controlla e firma' : 'Review and sign';
    }
    if (collateralReturnReady) {
      return _it
          ? 'Ritira il collaterale residuo'
          : 'Claim collateral remainder';
    }
    return switch (nextKind) {
      'repay' => _it ? 'Controlla la rata' : 'Review installment',
      'claim' => _it ? 'Incassa i pagamenti' : 'Claim payments',
      'renewal' => _it ? 'Controlla il rinnovo' : 'Review covenant renewal',
      _
          when state == 'repaid' ||
              state == 'defaulted' ||
              state == 'liquidated' =>
        _it ? 'Vedi cronologia' : 'View history',
      _ => _it ? 'Vedi dettagli' : 'View details',
    };
  }

  String covenantEffect(String action) => switch (action.trim()) {
    'origination' =>
      _it
          ? 'Crea il covenant radice e blocca tutto il collaterale.'
          : 'Creates the root covenant and locks all collateral.',
    'payment_preparation' =>
      _it
          ? 'Prepara l’UTXO di pagamento; non modifica ancora il covenant.'
          : 'Prepares the payment UTXO; the covenant is unchanged.',
    'installment' =>
      _it
          ? 'Spende il covenant corrente e crea il successore. Tutto il collaterale resta bloccato finché il saldo non raggiunge zero.'
          : 'Spends the current covenant and creates its successor. All collateral stays locked until the balance reaches zero.',
    'repayment' =>
      _it
          ? 'Spende il covenant corrente senza successore e restituisce tutto il collaterale.'
          : 'Spends the current covenant without a successor and returns all collateral.',
    'payment_claim' =>
      _it
          ? 'Incassa pagamenti già versati dal debitore; non modifica il saldo del prestito.'
          : 'Claims payments already made by the borrower; the loan balance does not change.',
    'renewal' =>
      _it
          ? 'Revoca la vecchia finestra, distrugge il covenant e crea il successore con una rata mancata in più.'
          : 'Revokes the old window, destroys the covenant and creates a successor with one more missed installment.',
    'default' =>
      _it
          ? 'Distrugge il covenant senza successore e divide il collaterale tra le parti.'
          : 'Destroys the covenant without a successor and splits the collateral between the parties.',
    'collateral_claim' =>
      _it
          ? 'Ritira la quota di collaterale già assegnata al debitore.'
          : 'Claims the collateral remainder already assigned to the borrower.',
    'liquidation' =>
      _it
          ? 'Trasferisce al creditore il collaterale assegnato dal regolamento.'
          : 'Transfers the collateral assigned to the lender by settlement.',
    'proof' =>
      _it
          ? 'Prova il possesso della chiave; non muove fondi.'
          : 'Proves key ownership; no funds move.',
    'swap' =>
      _it ? 'Esegue lo scambio verificato.' : 'Executes the verified swap.',
    _ =>
      _it
          ? 'Controlla l’effetto verificato dal wallet prima di firmare.'
          : 'Review the wallet-verified effect before signing.',
  };
}

const Map<String, String> _actionsEn = {
  'origination': 'Loan origination',
  'payment_preparation': 'Payment preparation',
  'installment': 'Installment payment',
  'repayment': 'Full repayment',
  'payment_claim': 'Claim installment payments',
  'renewal': 'Covenant renewal',
  'default': 'Default settlement',
  'collateral_claim': 'Claim collateral remainder',
  'liquidation': 'Collateral liquidation',
  'proof': 'Proof of key',
  'swap': 'Atomic swap',
  '': 'Signing request',
};

const Map<String, String> _actionsIt = {
  'origination': 'Apertura del prestito',
  'payment_preparation': 'Preparazione del pagamento',
  'installment': 'Pagamento della rata',
  'repayment': 'Rimborso completo',
  'payment_claim': 'Incasso delle rate',
  'renewal': 'Rinnovo del covenant',
  'default': 'Regolamento del default',
  'collateral_claim': 'Ritiro del collaterale residuo',
  'liquidation': 'Liquidazione del collaterale',
  'proof': 'Prova della chiave',
  'swap': 'Swap atomico',
  '': 'Richiesta di firma',
};

String _humanize(String raw, {required bool italian}) {
  if (raw.isEmpty) return italian ? 'Richiesta di firma' : 'Signing request';
  final words = raw.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (words.isEmpty) return italian ? 'Richiesta di firma' : 'Signing request';
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

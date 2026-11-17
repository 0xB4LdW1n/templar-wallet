import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../shared/widgets/app_password_gate.dart';
import '../../theme/app_layout.dart';

/// The app password before a LiquiDEX step signs with this wallet's own key:
/// making an offer, creating an exact coin for one, taking an offer,
/// cancelling one. Nothing is signed without it (CLAUDE.md, rule 3). A
/// hardware wallet approves on its device instead, as in Send, so it is not
/// asked here.
///
/// [what] names the thing signed: "the offer", "the swap", …
Future<bool> confirmSwapSignature(BuildContext context, String what) async {
  if (context.read<AppState>().isActiveWalletHardware) return true;
  return showSpendPasswordGate(
    context,
    message:
        'Templar is about to sign $what with the key stored on this '
        '${AppLayout.isMobilePlatform ? 'device' : 'computer'}.',
  );
}

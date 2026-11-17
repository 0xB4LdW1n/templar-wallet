// The Settings sections as the rail names them: Network is called Network,
// Templar Protocol wears the Templar cross like any other icon, and the
// Network page no longer carries a second door to Templar Protocol.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/features/settings/settings_screen.dart';
import 'package:templar_wallet/shared/widgets/seal_mark.dart';
import 'package:templar_wallet/theme/app_theme.dart';

Widget _settings(SettingsSection section) => ChangeNotifierProvider<AppState>(
  create: (_) => AppState()..setActiveWallet('w1', name: 'W', type: 'Software'),
  child: MaterialApp(
    theme: AppTheme.dark(),
    home: SettingsScreen(section: section),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the network section is named Network', () {
    expect(SettingsSection.network.label, 'Network');
  });

  testWidgets('Templar Protocol wears the cross, in the row\'s own ink', (
    t,
  ) async {
    t.view.physicalSize = const Size(1280, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_settings(SettingsSection.network));
    await t.pump(const Duration(milliseconds: 600));

    // One cross on the page: the rail's Templar Protocol row.
    final cross = t.widget<CrossGlyph>(find.byType(CrossGlyph));
    final row = find.ancestor(
      of: find.byType(CrossGlyph),
      matching: find.byType(Row),
    );
    expect(
      find.descendant(of: row.first, matching: find.text('Templar Protocol')),
      findsOneWidget,
    );
    // Drawn like the other rows' icons: same size, same quiet ink.
    final wifi = t.widget<Icon>(find.byIcon(Icons.tune_outlined));
    expect(cross.size, wifi.size);
    expect(cross.color, wifi.color);
  });

  testWidgets('the Network page has no door to Templar Protocol', (t) async {
    t.view.physicalSize = const Size(1280, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(_settings(SettingsSection.network));
    await t.pump(const Duration(milliseconds: 600));

    expect(find.text('Open Templar Protocol'), findsNothing);
    // What the page is for is still there.
    expect(find.text('Liquid network'), findsOneWidget);
    expect(find.text('Block explorers'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}

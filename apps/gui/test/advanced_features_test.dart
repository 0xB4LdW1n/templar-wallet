import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/features/settings/settings_screen.dart';
import 'package:templar_wallet/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Advanced owns three off-by-default persistent feature gates', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final state = AppState();
    await state.loadPrefs();
    expect(state.liquidDexEnabled, isFalse);
    expect(state.pegEnabled, isFalse);
    expect(state.loansEnabled, isFalse);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const SettingsScreen(section: SettingsSection.advanced),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Optional wallet features'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(3));

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.byType(Switch).at(index));
      await tester.pumpAndSettle();
    }
    expect(state.liquidDexEnabled, isTrue);
    expect(state.pegEnabled, isTrue);
    expect(state.loansEnabled, isTrue);

    final restored = AppState();
    await restored.loadPrefs();
    expect(restored.liquidDexEnabled, isTrue);
    expect(restored.pegEnabled, isTrue);
    expect(restored.loansEnabled, isTrue);
  });
}

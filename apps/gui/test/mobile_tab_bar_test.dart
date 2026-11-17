// The phone's tab bar: every destination is on screen with its label, a tap
// on another tab selects it, and a tap on the current one asks the shell to
// scroll to the top instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:templar_wallet/app/shell.dart';
import 'package:templar_wallet/shared/widgets/hybrid_kit.dart';
import 'package:templar_wallet/shared/widgets/mobile_tab_bar.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<(List<String>, List<int>)> pump(
    WidgetTester tester, {
    required String current,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final selected = <String>[];
    final reselected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: MobileTabBar(
            items: mobileNavItems(liquid: true, loans: true),
            currentRoute: current,
            onSelect: selected.add,
            onReselect: () => reselected.add(1),
          ),
        ),
      ),
    );
    return (selected, reselected);
  }

  testWidgets('shows all six destinations, labelled, on a 360 dp phone', (
    tester,
  ) async {
    await pump(tester, current: '/dashboard');
    for (final label in const [
      'Dashboard',
      'Loans',
      'Activity',
      'Coins',
      'Liquid',
      'Settings',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('only the current tab wears the mark', (tester) async {
    await pump(tester, current: '/history');
    final marks = tester
        .widgetList<CurrentMark>(find.byType(CurrentMark))
        .toList();
    expect(marks, hasLength(6));
    expect(marks.where((m) => m.active), hasLength(1));
    // Activity is the third of the six.
    expect(marks[2].active, isTrue);
  });

  testWidgets('a tap on another tab selects it', (tester) async {
    final (selected, reselected) = await pump(tester, current: '/dashboard');
    await tester.tap(find.text('Activity'));
    expect(selected, ['/history']);
    expect(reselected, isEmpty);
  });

  testWidgets('a tap on the current tab scrolls to top, never selects', (
    tester,
  ) async {
    final (selected, reselected) = await pump(tester, current: '/dashboard');
    await tester.tap(find.text('Dashboard'));
    expect(selected, isEmpty);
    expect(reselected, hasLength(1));
  });

  testWidgets('every tab is at least 48 dp tall', (tester) async {
    await pump(tester, current: '/dashboard');
    final tab = tester.getSize(
      find.ancestor(of: find.text('Coins'), matching: find.byType(InkWell)),
    );
    expect(tab.height, greaterThanOrEqualTo(48));
    expect(MobileTabBar.heightFor(0), lessThanOrEqualTo(64));
  });
}

// The live edge is the one thing in the app that loops, and only while what
// it marks is live: a pending row breathes, a thing being signed has a
// stroke running round it, a thing that landed draws its outline closed
// once. Under reduced motion each is a still frame.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/shared/widgets/live_edge.dart';

Widget _host(LiveEdgeMode mode, {bool reduced = false}) => MediaQuery(
  data: MediaQueryData(disableAnimations: reduced),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: LiveEdge(
        mode: mode,
        color: const Color(0xFF00FF00),
        borderRadius: BorderRadius.circular(12),
        child: const SizedBox(width: 200, height: 80),
      ),
    ),
  ),
);

void main() {
  // The suite draws edges still (flutter_test_config.dart); this file is
  // about the motion itself.
  setUp(() => LiveEdge.debugStill = false);
  tearDown(() => LiveEdge.debugStill = true);

  testWidgets('off draws nothing over its child', (t) async {
    await t.pumpWidget(_host(LiveEdgeMode.off));
    expect(
      find.descendant(
        of: find.byType(LiveEdge),
        matching: find.byType(CustomPaint),
      ),
      findsNothing,
    );
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('breathing and working keep ticking while they are shown', (
    t,
  ) async {
    for (final mode in [LiveEdgeMode.breathing, LiveEdgeMode.working]) {
      await t.pumpWidget(_host(mode));
      await t.pump(const Duration(seconds: 5));
      expect(t.binding.hasScheduledFrame, isTrue, reason: '$mode loops');
    }
    // Taken off screen, nothing is left running.
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('done draws itself closed once, then rests', (t) async {
    await t.pumpWidget(_host(LiveEdgeMode.done));
    expect(t.binding.hasScheduledFrame, isTrue);
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('from working to done the loop stops and the outline closes', (
    t,
  ) async {
    await t.pumpWidget(_host(LiveEdgeMode.working));
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpWidget(_host(LiveEdgeMode.done));
    await t.pumpAndSettle();
    expect(t.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion: every state is a still frame', (t) async {
    for (final mode in LiveEdgeMode.values) {
      await t.pumpWidget(_host(mode, reduced: true));
      await t.pump();
      expect(t.binding.hasScheduledFrame, isFalse, reason: '$mode is still');
    }
  });

  testWidgets('the edge never changes the size of what it marks', (t) async {
    for (final mode in LiveEdgeMode.values) {
      await t.pumpWidget(_host(mode));
      expect(t.getSize(find.byType(LiveEdge)), const Size(200, 80));
    }
    await t.pumpWidget(const SizedBox.shrink());
  });
}

// Applies to every test under test/.
//
// A live edge (a pending row's breathing outline, the stroke running round a
// coin that is on its way) loops for as long as the thing it marks is live,
// so a tree that holds one never settles and `pumpAndSettle` would wait on it
// until it times out. Tests draw each edge as its still frame instead; the
// one test that is about the motion (live_edge_test.dart) turns it back on.
import 'dart:async';

import 'package:templar_wallet/shared/widgets/live_edge.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LiveEdge.debugStill = true;
  await testMain();
}

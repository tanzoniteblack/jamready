import 'package:flutter_test/flutter_test.dart';
import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/screens/jam_timer_screen.dart';
import 'package:jam_ready/widgets/clock_display.dart';
import 'package:jam_ready/widgets/jam_controls.dart';
import 'package:jam_ready/widgets/swipe_button.dart';
import 'package:provider/provider.dart';

ScoreboardState scoreboardState(WidgetTester tester) {
  final context = tester.element(find.byType(JamTimerScreen));
  return Provider.of<ScoreboardState>(context, listen: false);
}

enum ActiveDisplay {
  timeToDerby,
  ready,
  jam,
  lineup,
  timeout,
  period,
  intermission,
  unofficialScore,
  gameOver,
  unknown,
}

/// Helper to return the current clock type shown (or pre/post game messages)
ActiveDisplay _getActiveDisplay(WidgetTester tester) {
  // Special non-clock displays have unique top-level text — check these first.
  if (find.text('GAME OVER').evaluate().isNotEmpty) {
    return ActiveDisplay.gameOver;
  }
  if (find.text('UNOFFICIAL').evaluate().isNotEmpty) {
    return ActiveDisplay.unofficialScore;
  }
  if (find.text('TIME TO DERBY').evaluate().isNotEmpty) {
    return ActiveDisplay.timeToDerby;
  }
  if (find.text('READY').evaluate().isNotEmpty) return ActiveDisplay.ready;

  // For clock displays, scope the label search to ClockDisplay to avoid false
  // positives from button text ("TIMEOUT", "JAM" etc. appear in controls too).
  bool clockLabel(String label) => find
      .descendant(
        of: find.byType(ClockDisplay),
        matching: find.textContaining(label),
      )
      .evaluate()
      .isNotEmpty;

  if (clockLabel('JAM')) return ActiveDisplay.jam;
  if (clockLabel('LINEUP')) return ActiveDisplay.lineup;
  if (clockLabel('TIMEOUT')) return ActiveDisplay.timeout;
  if (clockLabel('INTERMISSION')) return ActiveDisplay.intermission;
  if (clockLabel('PERIOD')) return ActiveDisplay.period;

  return ActiveDisplay.unknown;
}

Future<void> validateActiveDisplay(
  WidgetTester tester,
  ActiveDisplay expectedDisplay, {
  Duration? timeout,
}) async {
  try {
    await pumpUntil(
      tester,
      () => _getActiveDisplay(tester) == expectedDisplay,
      timeout: timeout ?? const Duration(seconds: 4),
    );
  } catch (e) {
    final actualActiveDisplay = _getActiveDisplay(tester);
    print(
      "Actual active display: $actualActiveDisplay, expected: $expectedDisplay}",
    );
    rethrow;
  }
}

Future<void> swipeButton(WidgetTester tester, Finder buttonFinder) async {
  expect(buttonFinder, findsOneWidget, reason: 'SwipeButton should be visible');

  final buttonRect = tester.getRect(buttonFinder);
  // Handle is 80px wide, starts at left edge
  const handleWidth = 80.0;
  final handleCenter = Offset(
    buttonRect.left + handleWidth / 2,
    buttonRect.center.dy,
  );
  final dragDistance = buttonRect.width - handleWidth;

  // Use dragFrom with absolute coordinates for more reliable dragging
  await tester.dragFrom(handleCenter, Offset(dragDistance * 0.9, 0));
  // Use pump() instead of pumpAndSettle() due to continuous animations
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> swipeToStartLineup(WidgetTester tester) async {
  // Find the start lineup SwipeButton
  final button = find
      .ancestor(
        of: find.text('SLIDE TO START LINEUP'),
        matching: find.byType(SwipeButton),
      )
      .first;
  await swipeButton(tester, button);
}

Future<void> tapButton(WidgetTester tester, Finder target) async {
  await pumpUntil(
    tester,
    () => target.evaluate().isNotEmpty,
    description:
        'Unable to find button with ${target.toString(describeSelf: true)}',
  );
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
}

Future<void> tapJamControl(WidgetTester tester, String label) async {
  // JamControls shows a confirmation state ("JAM STARTED"/"JAM ENDED") for
  // cooldownDuration after each jam transition. The confirmation is based on
  // DateTime.now() (real time); tester.pump(duration) advances real time on
  // device, so pumping past it ensures the button is back to its normal label.
  await tester.pump(
    JamControls.cooldownDuration + const Duration(milliseconds: 200),
  );

  await tapButton(tester, find.text(label.toUpperCase()));
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 100),
  String description = 'Timed out waiting for condition.',
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (condition()) return;
  }
  throw TestFailure(description);
}

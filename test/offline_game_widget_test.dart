/// Widget tests for the offline (local) game mode.
///
/// Run on host without a device:
///   flutter test test/offline_game_widget_test.dart
///
/// Tests are in two flavours:
///  • Navigation tests – launch the full app via app.main() and drive the UI
///  • Game-logic tests – create a LocalGameEngine directly and pump JamTimerScreen,
///    giving us a live engine reference without going through the Provider tree
///    (LocalGameEngine is not exposed as a Provider in the production app).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jam_ready/widgets/swipe_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jam_ready/main.dart' as app;
import 'package:jam_ready/models/game_config.dart';
import 'package:jam_ready/models/ruleset.dart';
import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/screens/jam_timer_screen.dart';
import 'package:jam_ready/services/local_game_engine.dart';

import 'helpers/common_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers – full-app navigation
// ---------------------------------------------------------------------------

/// Sets [clockName] to [timeMs] and pumps one frame so the state update
/// propagates to the widget tree. Use this when you want to reposition a
/// clock without waiting for it to expire (e.g. "set period to 1 second").
Future<void> _setClock(
  WidgetTester tester,
  LocalGameEngine engine,
  String clockName,
  int timeMs,
) async {
  engine.setClockTime(clockName, timeMs);
  await tester.pump(const Duration(milliseconds: 50));
}

/// Launches the full app and drives the UI through to the game screen.
/// Leaves the tester on JamTimerScreen.
Future<void> _launchOfflineGame(
  WidgetTester tester, {
  String team1 = 'Salt',
  String team2 = 'Pepper',
}) async {
  // Widget tests default to 800×600 (landscape). The app is designed for a
  // portrait phone, so set a taller viewport so buttons are in-bounds.
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({});
  app.main();

  await pumpUntil(
    tester,
    () => find.text('Jam Timer Operator').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 10),
  );
  await tester.tap(find.text('Jam Timer Operator'));

  await pumpUntil(
    tester,
    () => find.text('START LOCAL GAME').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 10),
  );

  await tester.tap(find.text('START LOCAL GAME'));

  // Wait for GameSetupScreen to appear, then settle the transition.
  // HomeScreen uses pushReplacement, so both screens are in the widget
  // tree during the animation – HomeScreen has its own TextFormFields
  // (host/port) that would be found first if we don't wait for it to leave.
  await pumpUntil(
    tester,
    () => find.text('START GAME').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 5),
  );
  await tester.pumpAndSettle();

  // Optionally override team names (defaults match GameSetupScreen placeholders)
  if (team1 != 'Salt') {
    await tester.enterText(find.byType(TextFormField).first, team1);
    await tester.pump();
  }
  if (team2 != 'Pepper') {
    await tester.enterText(find.byType(TextFormField).last, team2);
    await tester.pump();
  }

  await tester.tap(find.text('START GAME'));

  await pumpUntil(
    tester,
    () => find.byType(JamTimerScreen).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 5),
  );
}

// ---------------------------------------------------------------------------
// Helpers – direct game setup (engine reference available)
// ---------------------------------------------------------------------------

/// Creates a [LocalGameEngine] and pumps a [JamTimerScreen] directly.
/// Returns the engine so tests can drive game state programmatically.
Future<(ScoreboardState, LocalGameEngine)> _setupGame(
  WidgetTester tester, {
  Ruleset? ruleset,
  String team1 = 'Home',
  String team2 = 'Away',
}) async {
  final state = ScoreboardState();
  final config = GameConfig(
    ruleset: ruleset ?? Ruleset.wftda(),
    team1Name: team1,
    team2Name: team2,
  );
  final engine = LocalGameEngine(state, config);

  await tester.pumpWidget(
    MultiProvider(
      providers: [ChangeNotifierProvider.value(value: state)],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: JamTimerScreen(engine: engine),
      ),
    ),
  );

  await tester.pumpAndSettle();
  return (state, engine);
}

// ---------------------------------------------------------------------------
// Parameterised test helpers
// ---------------------------------------------------------------------------

/// Runs a single non-final period via UI: starts lineup, starts a jam,
/// fast-forwards period clock, stops jam, validates intermission display,
/// and drains the intermission clock.
Future<void> _runNonFinalPeriod(
  WidgetTester tester,
  LocalGameEngine engine,
  ScoreboardState state,
) async {
  // start jam line up and then jam
  await swipeToStartLineup(tester);
  await tapJamControl(tester, state.labelStart);
  await _setClock(tester, engine, 'Period', 0);
  // stop the jam
  await tapJamControl(tester, state.labelStop);
  await validateActiveDisplay(tester, ActiveDisplay.intermission);
  // end intermission
  await _setClock(tester, engine, 'Intermission', 0);
}

/// Runs a single period in the full-game flow, with intermediate display
/// validations. If [isFinal] is true, validates unofficial score instead of
/// intermission (and does not drain the intermission clock).
Future<void> _runFullGamePeriod(
  WidgetTester tester,
  LocalGameEngine engine,
  ScoreboardState state, {
  bool isFinal = false,
}) async {
  await swipeToStartLineup(tester);
  await validateActiveDisplay(tester, ActiveDisplay.lineup);
  await tapJamControl(tester, state.labelStart);
  await validateActiveDisplay(tester, ActiveDisplay.jam);
  await _setClock(tester, engine, 'Period', 0);
  expect(state.clocks['Jam']!.running, isTrue);
  await validateActiveDisplay(tester, ActiveDisplay.jam);
  await tapJamControl(tester, state.labelStop);
  if (isFinal) {
    await validateActiveDisplay(tester, ActiveDisplay.unofficialScore);
  } else {
    await validateActiveDisplay(tester, ActiveDisplay.intermission);
    await _setClock(tester, engine, 'Intermission', 0);
  }
}

Future<void> _testOvertimeFlow(WidgetTester tester, Ruleset ruleset) async {
  final (state, engine) = await _setupGame(tester, ruleset: ruleset);
  addTearDown(engine.dispose);

  await validateActiveDisplay(tester, ActiveDisplay.ready);
  for (int p = 1; p < ruleset.periodCount; p++) {
    await _runNonFinalPeriod(tester, engine, state);
  }

  // --- Final period ---
  await swipeToStartLineup(tester);
  await tapJamControl(tester, state.labelStart);
  await _setClock(tester, engine, 'Period', 0);
  await tapJamControl(tester, state.labelStop);
  await validateActiveDisplay(tester, ActiveDisplay.unofficialScore);

  // Both the overtime SwipeButton and the END GAME button must be visible.
  final overtimeButton = find.ancestor(
    of: find.textContaining('OVERTIME LINEUP'),
    matching: find.byType(SwipeButton),
  );
  expect(overtimeButton, findsOneWidget);
  expect(find.text('END GAME'), findsOneWidget);

  // Swipe to start the overtime lineup.
  await swipeButton(tester, overtimeButton);
  await validateActiveDisplay(tester, ActiveDisplay.lineup);

  expect(state.inOvertime, isTrue);
  expect(state.clocks['Period']!.running, isFalse);
  // Alert system should use the overtime lineup duration, not the regular one.
  expect(state.lineupOvertimeDuration, ruleset.lineupOvertimeDurationMs);

  // --- Run Overtime jam ---
  await tapJamControl(tester, state.labelStart);
  await validateActiveDisplay(tester, ActiveDisplay.jam);
  // Period clock must NOT restart during an overtime jam.
  expect(state.clocks['Period']!.running, isFalse);
  expect(state.clocks['Period']!.time, 0);
  await tapJamControl(tester, state.labelStop);

  // after overtime jam, back to the official score page
  await validateActiveDisplay(tester, ActiveDisplay.unofficialScore);

  // End the game
  await tapButton(tester, find.text('END GAME'));
  await validateActiveDisplay(tester, ActiveDisplay.gameOver);
}

Future<void> _testFullGameFlow(WidgetTester tester, Ruleset ruleset) async {
  final (state, engine) = await _setupGame(tester, ruleset: ruleset);
  addTearDown(engine.dispose);

  await validateActiveDisplay(tester, ActiveDisplay.ready);
  for (int p = 1; p < ruleset.periodCount; p++) {
    await _runFullGamePeriod(tester, engine, state);
  }
  await _runFullGamePeriod(tester, engine, state, isFinal: true);

  await tapButton(tester, find.text('END GAME'));
  await validateActiveDisplay(tester, ActiveDisplay.gameOver);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    // Mock the wakelock channel – LocalGameEngine.initialize() calls
    // WakelockPlus.enable(), which needs a channel handler even in widget tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (ByteData? message) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  // ---------------------------------------------------------------------------
  // Full-app navigation (UI-driven)
  // ---------------------------------------------------------------------------

  group('navigation', () {
    testWidgets('app starts on role picker', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('CHOOSE YOUR ROLE'), findsOneWidget);
      expect(find.text('Jam Timer Operator'), findsOneWidget);
      expect(find.text('Penalty Box'), findsOneWidget);
    });

    testWidgets('jam timer role navigates to game setup', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({});
      app.main();

      await pumpUntil(
        tester,
        () => find.text('Jam Timer Operator').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Jam Timer Operator'));

      await pumpUntil(
        tester,
        () => find.text('START LOCAL GAME').evaluate().isNotEmpty,
      );

      await tester.tap(find.text('START LOCAL GAME'));

      await pumpUntil(
        tester,
        () => find.text('START GAME').evaluate().isNotEmpty,
      );

      expect(find.text('WFTDA'), findsOneWidget);
      expect(find.text('START GAME'), findsOneWidget);
    });

    testWidgets('START GAME navigates to jam timer screen', (tester) async {
      await _launchOfflineGame(tester);

      expect(find.byType(JamTimerScreen), findsOneWidget);
      expect(find.text('JamReady'), findsOneWidget);
    });

    testWidgets('team names from setup appear on the game screen', (
      tester,
    ) async {
      await _launchOfflineGame(tester, team1: 'Rockets', team2: 'Thunder');
      // Pump a couple of frames for initialize() → notifyListeners() → rebuild.
      await tester.pump();
      await tester.pump();

      // Scope to JamTimerScreen to avoid matching the TextFormField from the
      // departing GameSetupScreen that may still be in the tree mid-animation.
      final screen = find.byType(JamTimerScreen);
      expect(
        find.descendant(of: screen, matching: find.text('Rockets')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: screen, matching: find.text('Thunder')),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Initial game state
  // ---------------------------------------------------------------------------

  group('initial game state', () {
    testWidgets('game starts in pre-game phase', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      expect(engine.phase, GamePhase.preGame);
      expect(state.inJam, false);
      expect(state.clocks['Period']!.running, false);
    });

    testWidgets('period clock starts at full ruleset duration', (tester) async {
      final ruleset = Ruleset.wftda();
      final (state, engine) = await _setupGame(tester, ruleset: ruleset);
      addTearDown(engine.dispose);

      expect(state.clocks['Period']!.time, ruleset.periodDurationMs);
      expect(state.clocks['Period']!.running, false);
    });

    testWidgets('connection status shows Offline Game', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      expect(state.connectionStatus, 'Offline Game');
    });

    testWidgets('team names appear on the game screen', (tester) async {
      final (_, engine) = await _setupGame(
        tester,
        team1: 'Rockets',
        team2: 'Thunder',
      );
      addTearDown(engine.dispose);
      await tester.pump();

      expect(find.text('Rockets'), findsOneWidget);
      expect(find.text('Thunder'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Starting a jam
  // ---------------------------------------------------------------------------

  group('starting a jam', () {
    testWidgets('startJam transitions from preGame to jam phase', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      await tester.pump();

      expect(engine.phase, GamePhase.jam);
      expect(state.inJam, true);
      expect(state.clocks['Jam']!.running, true);
      expect(state.clocks['Period']!.running, true);
    });

    testWidgets('jam number increments each time a jam starts', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      expect(state.clocks['Jam']!.number, 1);

      engine.stopJam();
      engine.startJam();
      expect(state.clocks['Jam']!.number, 2);
    });

    testWidgets('jam clock resets to full duration on each new jam', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(
        tester,
        ruleset: Ruleset.wftda(),
      );
      addTearDown(engine.dispose);

      engine.startJam();
      engine.adjustClock('Jam', -30 * 1000);
      engine.stopJam();
      engine.startJam();

      expect(state.clocks['Jam']!.time, Ruleset.wftda().jamDurationMs);
    });
  });

  // ---------------------------------------------------------------------------
  // Stopping a jam
  // ---------------------------------------------------------------------------

  group('stopping a jam', () {
    testWidgets('stopJam transitions to lineup phase', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      engine.stopJam();
      await tester.pump();

      expect(engine.phase, GamePhase.lineup);
      expect(state.inJam, false);
      expect(state.clocks['Lineup']!.running, true);
    });

    testWidgets('undo is available after stopping a jam', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      engine.stopJam();

      expect(state.labelUndo, 'UNDO: Unstop Jam');
    });

    testWidgets('undoing a jam stop restores the running jam', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      engine.stopJam();
      engine.undo();
      await tester.pump();

      expect(engine.phase, GamePhase.jam);
      expect(state.inJam, true);
      expect(state.clocks['Jam']!.running, true);
    });
  });

  // ---------------------------------------------------------------------------
  // Undo: unstart jam
  // ---------------------------------------------------------------------------

  group('undo: unstart jam', () {
    testWidgets('labelUndo is UNDO: Unstart Jam after startJam', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      await tester.pump();

      expect(state.labelUndo, 'UNDO: Unstart Jam');
    });

    testWidgets('undo after startJam returns to lineup', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      await tester.pump();
      expect(engine.phase, GamePhase.jam);

      engine.undo();
      await tester.pump();

      expect(engine.phase, GamePhase.lineup);
      expect(state.inJam, isFalse);
      expect(state.clocks['Jam']!.running, isFalse);
      expect(state.clocks['Lineup']!.running, isTrue);
      expect(state.clocks['Jam']!.number, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Undo: unstart lineup
  // ---------------------------------------------------------------------------

  group('undo: unstart lineup', () {
    testWidgets('labelUndo is UNDO: Unstart Lineup after lineup start', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.stopJam(); // preGame → lineup
      await tester.pump();

      expect(state.labelUndo, 'UNDO: Unstart Lineup');
    });

    testWidgets('undo after lineup start returns to preGame', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.stopJam(); // preGame → lineup
      await tester.pump();
      expect(engine.phase, GamePhase.lineup);

      engine.undo();
      await tester.pump();

      expect(engine.phase, GamePhase.preGame);
      expect(state.clocks['Lineup']!.running, isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Timeout flow
  // ---------------------------------------------------------------------------

  group('timeout', () {
    testWidgets('timeout pauses period clock and starts timeout clock', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      engine.startTimeout();
      await tester.pump();

      expect(engine.phase, GamePhase.timeout);
      expect(state.clocks['Period']!.running, false);
      expect(state.clocks['Timeout']!.running, true);
    });

    testWidgets('ending a timeout returns to lineup', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      engine.startTimeout();
      engine.endTimeout();
      await tester.pump();

      expect(engine.phase, GamePhase.lineup);
      expect(state.clocks['Lineup']!.running, true);
    });

    testWidgets('team 1 timeout decrements timeout count', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      final initial = state.team1.timeouts;
      engine.startJam();
      engine.setTimeoutOwner('1');
      await tester.pump();

      expect(state.team1.timeouts, initial - 1);
    });

    testWidgets(
      'switching from team 1 timeout to team 2 restores team 1 count',
      (tester) async {
        final (state, engine) = await _setupGame(tester);
        addTearDown(engine.dispose);

        final t1Initial = state.team1.timeouts;
        final t2Initial = state.team2.timeouts;
        engine.startJam();
        engine.setTimeoutOwner('1');
        engine.setTimeoutOwner('2');
        await tester.pump();

        expect(state.team1.timeouts, t1Initial);
        expect(state.team2.timeouts, t2Initial - 1);
      },
    );

    testWidgets(
      'switching from team timeout to official timeout restores team count',
      (tester) async {
        final (state, engine) = await _setupGame(tester);
        addTearDown(engine.dispose);

        final initial = state.team1.timeouts;
        engine.startJam();
        engine.setTimeoutOwner('1');
        engine.setTimeoutOwner('O');
        await tester.pump();

        expect(state.team1.timeouts, initial);
      },
    );

    testWidgets(
      'switching from team timeout to official review restores timeout count',
      (tester) async {
        final (state, engine) = await _setupGame(tester);
        addTearDown(engine.dispose);

        final initialTO = state.team1.timeouts;
        final initialOR = state.team1.officialReviews;
        engine.startJam();
        engine.setTimeoutOwner('1'); // team 1 timeout
        engine.setTimeoutOwner('1', isOfficialReview: true); // switch to OR
        await tester.pump();

        expect(state.team1.timeouts, initialTO); // timeout count restored
        expect(
          state.team1.officialReviews,
          initialOR - 1,
        ); // review count decremented
      },
    );

    testWidgets('timeout from lineup does not require a prior jam', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.stopJam(); // preGame → lineup (no jam ever ran)
      await tester.pump();
      expect(engine.phase, GamePhase.lineup);

      engine.startTimeout();
      await tester.pump();

      expect(engine.phase, GamePhase.timeout);
      expect(state.clocks['Timeout']!.running, isTrue);
      expect(state.clocks['Lineup']!.running, isFalse);
    });

    testWidgets('startTimeout when already in timeout resets clock and owner', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startTimeout();
      engine.setTimeoutOwner('1'); // assign team 1, decrement their count
      engine.adjustClock('Timeout', 30000); // advance clock 30s
      await tester.pump();
      expect(state.clocks['Timeout']!.time, greaterThan(0));

      engine.startTimeout(); // re-timeout resets clock and owner to O
      await tester.pump();

      expect(engine.phase, GamePhase.timeout);
      expect(state.clocks['Timeout']!.time, 0);
      expect(state.timeoutOwner, 'O');
    });

    testWidgets('undo while in team timeout restores the team timeout count', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      final initial = state.team1.timeouts;
      engine.startJam();
      engine.setTimeoutOwner('1'); // stops jam, assigns T1 timeout
      await tester.pump();
      expect(state.team1.timeouts, initial - 1);
      expect(engine.phase, GamePhase.timeout);

      engine.undo(); // unstopJam: should restore jam AND T1 count
      await tester.pump();

      expect(engine.phase, GamePhase.jam);
      expect(state.team1.timeouts, initial);
      expect(state.timeoutOwner, '');
      expect(state.clocks['Timeout']!.running, isFalse);
    });

    testWidgets(
      'undo while in team official review restores the review count',
      (tester) async {
        final ruleset = Ruleset.wftda();
        final (state, engine) = await _setupGame(tester, ruleset: ruleset);
        addTearDown(engine.dispose);

        engine.startJam();
        engine.setTimeoutOwner('1', isOfficialReview: true);
        await tester.pump();
        expect(state.team1.officialReviews, ruleset.reviewsPerPeriod - 1);

        engine.undo();
        await tester.pump();

        expect(engine.phase, GamePhase.jam);
        expect(state.team1.officialReviews, ruleset.reviewsPerPeriod);
        expect(state.isOfficialReview, isFalse);
        expect(state.clocks['Timeout']!.running, isFalse);
      },
    );

    testWidgets(
      'undo after mid-timeout reassignment restores the final assigned team count',
      (tester) async {
        final (state, engine) = await _setupGame(tester);
        addTearDown(engine.dispose);

        final t1Initial = state.team1.timeouts;
        final t2Initial = state.team2.timeouts;
        engine.startJam();
        engine.setTimeoutOwner('1'); // T1 assigned (count --)
        engine.setTimeoutOwner('2'); // T2 assigned, T1 restored (T1++, T2--)
        await tester.pump();
        expect(state.team1.timeouts, t1Initial);
        expect(state.team2.timeouts, t2Initial - 1);

        engine.undo(); // should restore T2 count and reinstate jam
        await tester.pump();

        expect(engine.phase, GamePhase.jam);
        expect(state.team1.timeouts, t1Initial);
        expect(state.team2.timeouts, t2Initial);
        expect(state.clocks['Timeout']!.running, isFalse);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Official reviews
  // ---------------------------------------------------------------------------

  group('official reviews', () {
    testWidgets('team 1 official review decrements review count', (
      tester,
    ) async {
      final ruleset = Ruleset.wftda();
      final (state, engine) = await _setupGame(tester, ruleset: ruleset);
      addTearDown(engine.dispose);

      engine.setTimeoutOwner('1', isOfficialReview: true);
      await tester.pump();

      expect(state.team1.officialReviews, ruleset.reviewsPerPeriod - 1);
    });

    testWidgets('team 2 official review decrements review count', (
      tester,
    ) async {
      final ruleset = Ruleset.wftda();
      final (state, engine) = await _setupGame(tester, ruleset: ruleset);
      addTearDown(engine.dispose);

      engine.setTimeoutOwner('2', isOfficialReview: true);
      await tester.pump();

      expect(state.team2.officialReviews, ruleset.reviewsPerPeriod - 1);
    });

    testWidgets(
      'switching from team 1 OR to official timeout restores review count',
      (tester) async {
        final ruleset = Ruleset.wftda();
        final (state, engine) = await _setupGame(tester, ruleset: ruleset);
        addTearDown(engine.dispose);

        engine.setTimeoutOwner('1', isOfficialReview: true);
        engine.setTimeoutOwner('O');
        await tester.pump();

        expect(state.team1.officialReviews, ruleset.reviewsPerPeriod);
      },
    );

    testWidgets(
      'switching from team 1 OR to team 2 OR restores team 1 and decrements team 2',
      (tester) async {
        final ruleset = Ruleset.wftda();
        final (state, engine) = await _setupGame(tester, ruleset: ruleset);
        addTearDown(engine.dispose);

        engine.setTimeoutOwner('1', isOfficialReview: true);
        engine.setTimeoutOwner('2', isOfficialReview: true);
        await tester.pump();

        expect(state.team1.officialReviews, ruleset.reviewsPerPeriod);
        expect(state.team2.officialReviews, ruleset.reviewsPerPeriod - 1);
      },
    );

    testWidgets(
      'switching from team 1 OR to team 1 timeout restores review and decrements timeout',
      (tester) async {
        final ruleset = Ruleset.wftda();
        final (state, engine) = await _setupGame(tester, ruleset: ruleset);
        addTearDown(engine.dispose);

        final initialTO = state.team1.timeouts;
        engine.setTimeoutOwner('1', isOfficialReview: true); // OR: review --
        engine.setTimeoutOwner(
          '1',
        ); // switch to TO: review restored, timeout --
        await tester.pump();

        expect(state.team1.officialReviews, ruleset.reviewsPerPeriod);
        expect(state.team1.timeouts, initialTO - 1);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Retained official review
  // ---------------------------------------------------------------------------

  group('retained official review', () {
    testWidgets('retaining review restores the review count', (tester) async {
      final ruleset = Ruleset.wftda();
      final (state, engine) = await _setupGame(tester, ruleset: ruleset);
      addTearDown(engine.dispose);

      engine.setTimeoutOwner('1', isOfficialReview: true);
      await tester.pump();
      expect(state.team1.officialReviews, ruleset.reviewsPerPeriod - 1);

      engine.setRetainedReview(1, true);
      await tester.pump();

      expect(state.team1.retainedOfficialReview, isTrue);
      expect(state.team1.officialReviews, ruleset.reviewsPerPeriod);
    });

    testWidgets('not retaining review leaves count decremented', (
      tester,
    ) async {
      final ruleset = Ruleset.wftda();
      final (state, engine) = await _setupGame(tester, ruleset: ruleset);
      addTearDown(engine.dispose);

      engine.setTimeoutOwner('1', isOfficialReview: true);
      await tester.pump();

      engine.setRetainedReview(1, false);
      await tester.pump();

      expect(state.team1.retainedOfficialReview, isFalse);
      expect(state.team1.officialReviews, ruleset.reviewsPerPeriod - 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Score adjustments
  // ---------------------------------------------------------------------------

  group('score', () {
    testWidgets('adjustScore updates team score', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.adjustScore(1, 4);
      await tester.pump();

      expect(state.team1.score, 4);
    });

    testWidgets('score cannot go below zero', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.adjustScore(2, -100);
      await tester.pump();

      expect(state.team2.score, 0);
    });

    testWidgets('adjustClock clamps to zero with a large negative delta', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.adjustClock('Period', -99999999);
      await tester.pump();

      expect(state.clocks['Period']!.time, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Period transitions (drives engine directly; verifies widget still renders)
  // ---------------------------------------------------------------------------

  group('period transitions', () {
    testWidgets('period expiring during a jam leads to intermission', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam();
      await tester.pump();

      expect(engine.phase, GamePhase.intermission);
      expect(state.clocks['Intermission']!.running, true);
    });

    testWidgets('undo after period-ending jam reverses intermission', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam();
      engine.undo();
      await tester.pump();

      expect(engine.phase, GamePhase.jam);
      expect(state.clocks['Intermission']!.running, false);
    });

    testWidgets('final period ending leads to unofficial score then game over', (
      tester,
    ) async {
      // 1-period ruleset so any period end → unofficial score immediately
      final ruleset = Ruleset.custom(
        id: 'test_1p',
        name: 'Test 1P',
        periodCount: 1,
        periodDurationMs: 30 * 60 * 1000,
        jamDurationMs: 2 * 60 * 1000,
        jamsResetPerPeriod: false,
        lineupDurationMs: 30 * 1000,
        lineupOvertimeDurationMs: 60 * 1000,
        timeoutsPerPeriod: 3,
        reviewsPerPeriod: 1,
        intermissionDurationsMs: [],
      );
      final (state, engine) = await _setupGame(tester, ruleset: ruleset);
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam();
      await tester.pump();

      // Final period → unofficial score; operator must explicitly end the game.
      expect(engine.phase, GamePhase.unofficialScore);
      expect(state.noMoreJam, true);

      engine.endGame();
      await tester.pump();

      expect(engine.phase, GamePhase.gameOver);
      expect(state.connectionStatus, 'Game Over');
    });

    testWidgets('undo reverses unofficial score and restores jam', (
      tester,
    ) async {
      final ruleset = Ruleset.custom(
        id: 'test_1p',
        name: 'Test 1P',
        periodCount: 1,
        periodDurationMs: 30 * 60 * 1000,
        jamDurationMs: 2 * 60 * 1000,
        jamsResetPerPeriod: false,
        lineupDurationMs: 30 * 1000,
        lineupOvertimeDurationMs: 60 * 1000,
        timeoutsPerPeriod: 3,
        reviewsPerPeriod: 1,
        intermissionDurationsMs: [],
      );
      final (state, engine) = await _setupGame(tester, ruleset: ruleset);
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam();
      engine.undo();
      await tester.pump();

      expect(engine.phase, GamePhase.jam);
      expect(state.noMoreJam, false);
      expect(state.connectionStatus, 'Offline Game');
    });

    testWidgets('period 2 clock resets to full ruleset duration', (
      tester,
    ) async {
      final ruleset = Ruleset.wftda();
      final (state, engine) = await _setupGame(tester, ruleset: ruleset);
      addTearDown(engine.dispose);

      // Run period 1 through to intermission
      engine.stopJam(); // preGame → lineup
      engine.startJam(); // lineup → jam (period clock starts)
      engine.setClockTime('Period', 0);
      await tester.pump(const Duration(milliseconds: 50)); // period expires
      engine.stopJam(); // jam → period ends → intermission
      await tester.pump(const Duration(milliseconds: 50));

      // End intermission → period 2 starts
      engine.setClockTime('Intermission', 0);
      await tester.pump(const Duration(milliseconds: 50));

      expect(engine.phase, GamePhase.preGame);
      expect(state.clocks['Period']!.number, 2);
      expect(state.clocks['Period']!.time, ruleset.periodDurationMs);
    });

    testWidgets('timeouts and reviews reset at start of period 2', (
      tester,
    ) async {
      final ruleset = Ruleset.wftda();
      final (state, engine) = await _setupGame(tester, ruleset: ruleset);
      addTearDown(engine.dispose);

      // Burn team 1's timeout and review in period 1
      engine.setTimeoutOwner('1'); // starts timeout, decrements T1 timeouts
      engine.endTimeout();
      await tester.pump();
      expect(state.team1.timeouts, ruleset.timeoutsPerPeriod - 1);

      engine.setTimeoutOwner('1', isOfficialReview: true);
      engine.endTimeout();
      await tester.pump();
      expect(state.team1.officialReviews, ruleset.reviewsPerPeriod - 1);

      // Run period 1 to completion
      engine.startJam(); // from lineup (endTimeout leaves us there)
      engine.setClockTime('Period', 0);
      await tester.pump(const Duration(milliseconds: 50)); // period expires
      engine.stopJam();
      await tester.pump(const Duration(milliseconds: 50));

      // End intermission → period 2
      engine.setClockTime('Intermission', 0);
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.team1.timeouts, ruleset.timeoutsPerPeriod);
      expect(state.team2.timeouts, ruleset.timeoutsPerPeriod);
      expect(state.team1.officialReviews, ruleset.reviewsPerPeriod);
      expect(state.team2.officialReviews, ruleset.reviewsPerPeriod);
    });
  });

  // ---------------------------------------------------------------------------
  // Idempotency
  // ---------------------------------------------------------------------------

  group('idempotency', () {
    testWidgets('startJam when jam is already running is a no-op', (
      tester,
    ) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startJam();
      await tester.pump();
      expect(engine.phase, GamePhase.jam);
      expect(state.clocks['Jam']!.number, 1);

      engine.startJam(); // second call should be ignored
      await tester.pump();

      expect(engine.phase, GamePhase.jam);
      expect(state.clocks['Jam']!.number, 1);
    });

    testWidgets('startJam from timeout is a no-op', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.startTimeout();
      await tester.pump();
      expect(engine.phase, GamePhase.timeout);

      engine.startJam();
      await tester.pump();

      expect(engine.phase, GamePhase.timeout);
      expect(state.inJam, isFalse);
    });

    testWidgets('stopJam from lineup is a no-op', (tester) async {
      final (state, engine) = await _setupGame(tester);
      addTearDown(engine.dispose);

      engine.stopJam(); // preGame → lineup
      await tester.pump();
      expect(engine.phase, GamePhase.lineup);
      final lineupLabel = state.labelUndo;

      engine.stopJam(); // second call from lineup: no-op
      await tester.pump();

      expect(engine.phase, GamePhase.lineup);
      expect(state.clocks['Lineup']!.running, isTrue);
      expect(state.labelUndo, lineupLabel); // undo state unchanged
    });
  });

  group('full game flows', () {
    group('overtime', () {
      testWidgets('overtime lineup and jam flow - WFTDA', (tester) async {
        await _testOvertimeFlow(tester, Ruleset.wftda());
      });
      testWidgets('overtime lineup and jam flow - RDCL', (tester) async {
        await _testOvertimeFlow(tester, Ruleset.rdcl());
      });
    });

    testWidgets('full game run through via UI - WFTDA', (tester) async {
      await _testFullGameFlow(tester, Ruleset.wftda());
    });
    testWidgets('full game run through via UI - RDCL', (tester) async {
      await _testFullGameFlow(tester, Ruleset.rdcl());
    });
  });
}

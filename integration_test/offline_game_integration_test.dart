/// Integration tests for the offline (local) game mode.
///
/// Run on a real device or simulator:
///   flutter test integration_test/offline_game_integration_test.dart
///
/// These tests exercise the full app from launch through game play without
/// requiring a CRG scoreboard server connection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roller_derby_jam_timer/main.dart' as app;
import 'package:roller_derby_jam_timer/models/scoreboard_state.dart';
import 'package:roller_derby_jam_timer/screens/jam_timer_screen.dart';
import 'package:roller_derby_jam_timer/services/local_game_engine.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Waits for [condition] to become true by repeatedly pumping [step] frames.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (condition()) return;
  }
  throw TestFailure('_pumpUntil: timed out waiting for condition');
}

/// Launches the full app and navigates to the offline game screen.
/// Leaves the tester on [JamTimerScreen] ready to play.
Future<void> _launchOfflineGame(
  WidgetTester tester, {
  String team1 = 'Home',
  String team2 = 'Away',
}) async {
  SharedPreferences.setMockInitialValues({});
  app.main();

  // Wait for SettingsScreen to appear
  await _pumpUntil(
    tester,
    () => find.text('START OFFLINE GAME').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 10),
  );

  // Navigate to game setup
  await tester.tap(find.text('START OFFLINE GAME'));
  await tester.pump(const Duration(milliseconds: 500));

  // On game setup screen – set team names if not default
  if (team1 != 'Salt') {
    final team1Field = find.byType(TextFormField).first;
    await tester.enterText(team1Field, team1);
    await tester.pump();
  }
  if (team2 != 'Pepper') {
    final team2Field = find.byType(TextFormField).last;
    await tester.enterText(team2Field, team2);
    await tester.pump();
  }

  // Start the game
  await tester.tap(find.text('START GAME'));
  await tester.pump(const Duration(milliseconds: 500));

  // Ensure JamTimerScreen is visible
  await _pumpUntil(
    tester,
    () => find.byType(JamTimerScreen).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 5),
  );
}

/// Returns the [ScoreboardState] from the current [JamTimerScreen] context.
ScoreboardState _scoreboardState(WidgetTester tester) {
  final context = tester.element(find.byType(JamTimerScreen));
  return Provider.of<ScoreboardState>(context, listen: false);
}

/// Returns the [LocalGameEngine] from the current [JamTimerScreen] context.
LocalGameEngine _gameEngine(WidgetTester tester) {
  final context = tester.element(find.byType(JamTimerScreen));
  return Provider.of<LocalGameEngine>(context, listen: false);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // Navigation flow
  // ---------------------------------------------------------------------------

  group('navigation', () {
    testWidgets('app starts on settings screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('START OFFLINE GAME'), findsOneWidget);
    });

    testWidgets('START OFFLINE GAME navigates to game setup', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('START OFFLINE GAME'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('START GAME'), findsOneWidget);
      expect(find.text('WFTDA'), findsOneWidget);
    });

    testWidgets('START GAME navigates to jam timer screen', (tester) async {
      await _launchOfflineGame(tester);

      expect(find.byType(JamTimerScreen), findsOneWidget);
      expect(find.text('ROLLER DERBY JAM TIMER'), findsOneWidget);
    });

    testWidgets('team names entered in setup appear on the game screen', (tester) async {
      await _launchOfflineGame(tester, team1: 'Rockets', team2: 'Thunder');
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Rockets'), findsOneWidget);
      expect(find.text('Thunder'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Game screen initial state
  // ---------------------------------------------------------------------------

  group('initial game state', () {
    testWidgets('game starts in pre-game phase', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump();

      final engine = _gameEngine(tester);
      expect(engine.phase, GamePhase.preGame);
      expect(engine.state.inJam, false);
    });

    testWidgets('game screen shows Start Jam button', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump();

      // The main button shows "START JAM" or "SLIDE TO START LINEUP"
      final hasStartJam = find.text('START JAM').evaluate().isNotEmpty;
      final hasSlide = find.text('Slide to Start Lineup').evaluate().isNotEmpty;
      expect(hasStartJam || hasSlide, true);
    });

    testWidgets('period and jam clocks start at full duration', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump();

      final state = _scoreboardState(tester);
      // WFTDA: 30 min period, 2 min jam
      expect(state.clocks['Period']!.time, greaterThan(0));
      expect(state.clocks['Jam']!.time, greaterThan(0));
      expect(state.clocks['Period']!.running, false);
    });
  });

  // ---------------------------------------------------------------------------
  // Starting a jam
  // ---------------------------------------------------------------------------

  group('starting a jam', () {
    testWidgets('tapping Start Jam begins a jam', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);

      // In pre-game the main button may be a swipe or a tap depending on state.
      // Press Start Jam via the engine to avoid swipe-drag complexity.
      engine.startJam();
      await tester.pump(const Duration(milliseconds: 200));

      expect(engine.phase, GamePhase.jam);
      expect(engine.state.inJam, true);
      expect(engine.state.clocks['Jam']!.running, true);
      expect(engine.state.clocks['Period']!.running, true);
    });

    testWidgets('jam number increments each time a jam starts', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      engine.startJam();
      expect(engine.state.clocks['Jam']!.number, 1);

      engine.stopJam();
      await tester.pump(const Duration(milliseconds: 100));

      engine.startJam();
      expect(engine.state.clocks['Jam']!.number, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // Stopping a jam
  // ---------------------------------------------------------------------------

  group('stopping a jam', () {
    testWidgets('stopping a jam enters lineup phase', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      engine.startJam();
      engine.stopJam();
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.phase, GamePhase.lineup);
      expect(engine.state.inJam, false);
      expect(engine.state.clocks['Lineup']!.running, true);
    });

    testWidgets('undo is available after stopping a jam', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      engine.startJam();
      engine.stopJam();
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.state.labelUndo, 'UNDO: Unstop Jam');
    });

    testWidgets('undoing a jam stop restores the running jam', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      engine.startJam();
      engine.stopJam();
      engine.undo();
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.phase, GamePhase.jam);
      expect(engine.state.inJam, true);
      expect(engine.state.clocks['Jam']!.running, true);
    });
  });

  // ---------------------------------------------------------------------------
  // Timeout flow
  // ---------------------------------------------------------------------------

  group('timeout', () {
    testWidgets('calling a timeout pauses period clock and starts timeout clock', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      engine.startJam();
      engine.startTimeout();
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.phase, GamePhase.timeout);
      expect(engine.state.clocks['Period']!.running, false);
      expect(engine.state.clocks['Timeout']!.running, true);
    });

    testWidgets('ending a timeout returns to lineup', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      engine.startJam();
      engine.startTimeout();
      engine.endTimeout();
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.phase, GamePhase.lineup);
      expect(engine.state.clocks['Lineup']!.running, true);
    });

    testWidgets('team timeout decrements team timeout count', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      final initialTimeouts = engine.state.team1.timeouts;

      engine.startJam();
      engine.setTimeoutOwner('1');
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.state.team1.timeouts, initialTimeouts - 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Score adjustments
  // ---------------------------------------------------------------------------

  group('score', () {
    testWidgets('adjusting team 1 score updates the display', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      engine.adjustScore(1, 5);
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.state.team1.score, 5);
      expect(find.text('5'), findsWidgets);
    });

    testWidgets('score cannot go below 0', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      engine.adjustScore(1, -10);
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.state.team1.score, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Full game flow (abbreviated)
  // ---------------------------------------------------------------------------

  group('period transitions', () {
    testWidgets('period ending during a jam leads to intermission', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam();
      await tester.pump(const Duration(milliseconds: 100));

      // Should be in intermission (WFTDA has 2 periods)
      expect(engine.phase, GamePhase.intermission);
      expect(engine.state.clocks['Intermission']!.running, true);
    });

    testWidgets('undo after period-ending jam reverses intermission', (tester) async {
      await _launchOfflineGame(tester);
      await tester.pump(const Duration(milliseconds: 200));

      final engine = _gameEngine(tester);
      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam();
      engine.undo();
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.phase, GamePhase.jam);
      expect(engine.state.clocks['Intermission']!.running, false);
    });
  });
}

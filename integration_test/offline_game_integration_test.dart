/// Integration tests for the offline (local) game mode.
///
/// Run on a real device or simulator:
///   flutter test integration_test/offline_game_integration_test.dart
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
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jam_ready/main.dart' as app;
import 'package:jam_ready/models/game_config.dart';
import 'package:jam_ready/models/ruleset.dart';
import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/screens/jam_timer_screen.dart';
import 'package:jam_ready/services/local_game_engine.dart';

import 'utilities/common_helpers.dart';

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

/// Sets [clockName] to [toMs] and then pumps until the clock is no longer
/// running (i.e. it has expired and the engine has processed the expiration).
/// Use this to fast-forward a clock through its endpoint, e.g. to trigger
/// period end or intermission end without waiting the full duration.
Future<void> _drainClock(
  WidgetTester tester,
  LocalGameEngine engine,
  String clockName, {
  int toMs = 500,
  Duration timeout = const Duration(seconds: 5),
}) async {
  engine.setClockTime(clockName, toMs);
  await pumpUntil(
    tester,
    () => !engine.state.clocks[clockName]!.running,
    timeout: timeout,
  );
}

/// Launches the full app and drives the UI through to the game screen.
/// Leaves the tester on JamTimerScreen.
Future<void> _launchOfflineGame(
  WidgetTester tester, {
  String team1 = 'Salt',
  String team2 = 'Pepper',
}) async {
  SharedPreferences.setMockInitialValues({});
  app.main();

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
// Tests
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Mock the wakelock channel – harmless on real device, required in simulator.
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
    testWidgets('app starts on settings screen', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('START LOCAL GAME'), findsOneWidget);
    });

    testWidgets('START LOCAL GAME navigates to game setup', (tester) async {
      SharedPreferences.setMockInitialValues({});
      app.main();

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

      expect(find.text('Rockets'), findsOneWidget);
      expect(find.text('Thunder'), findsOneWidget);
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

    testWidgets('final period ending leads to unofficial score then game over', (tester) async {
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
        timeoutsPerGame: 3,
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

    testWidgets('undo reverses unofficial score and restores jam', (tester) async {
      final ruleset = Ruleset.custom(
        id: 'test_1p',
        name: 'Test 1P',
        periodCount: 1,
        periodDurationMs: 30 * 60 * 1000,
        jamDurationMs: 2 * 60 * 1000,
        jamsResetPerPeriod: false,
        lineupDurationMs: 30 * 1000,
        lineupOvertimeDurationMs: 60 * 1000,
        timeoutsPerGame: 3,
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
  });

  testWidgets('full game run through via UI', (tester) async {
    // TODO: Start local game via menu options
    final (state, engine) = await _setupGame(tester);

    addTearDown(engine.dispose);

    // game starts in ready state
    await validateActiveDisplay(tester, .ready);
    // start initial lineup
    await swipeToStartLineup(tester);
    await validateActiveDisplay(tester, .lineup);

    // start a jam
    await tapJamControl(tester, state.labelStart);
    await validateActiveDisplay(tester, .jam);
    expect(state.clocks['Jam']!.running, isTrue);

    // fast forward period clock without effecting jam clock
    await _setClock(tester, engine, 'Period', 0);
    expect(state.clocks['Jam']!.running, isTrue);
    await validateActiveDisplay(tester, .jam);

    // end the jam and start intermission
    await tapJamControl(tester, state.labelStop);
    await validateActiveDisplay(tester, .intermission);

    // short circuit intermission
    await _setClock(tester, engine, 'Intermission', 0);

    // start up the next period lineup
    await swipeToStartLineup(tester);
    await validateActiveDisplay(tester, .lineup);
    // start first jam of 2nd period
    await tapJamControl(tester, state.labelStart);
    await validateActiveDisplay(tester, .jam);

    // fast forward period clock without effecting jam clock
    await _setClock(tester, engine, 'Period', 0);
    expect(state.clocks['Jam']!.running, isTrue);
    await validateActiveDisplay(tester, .jam);

    // stop jam, see ability to start overtime jam or end game
    await tapJamControl(tester, state.labelStop);
    await validateActiveDisplay(tester, .unofficialScore);

    // tap End Game and confirm the game over display
    await tapButton(tester, find.text('END GAME'));
    await validateActiveDisplay(tester, .gameOver);
  });
}

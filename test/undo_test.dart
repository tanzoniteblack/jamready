import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jam_ready/models/game_config.dart';
import 'package:jam_ready/models/ruleset.dart';
import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/services/local_game_engine.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns a WFTDA engine (2 periods) ready to use.
Future<(ScoreboardState, LocalGameEngine)> _makeEngine({Ruleset? ruleset}) async {
  final state = ScoreboardState();
  final config = GameConfig(
    ruleset: ruleset ?? Ruleset.wftda(),
    team1Name: 'Home',
    team2Name: 'Away',
  );
  final engine = LocalGameEngine(state, config);
  await engine.initialize();
  return (state, engine);
}

/// A single-period ruleset so that ending any jam with period at 0 → game over.
Ruleset _oneperiodRuleset() => Ruleset.custom(
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Mock the Pigeon-based wakelock_plus platform channel used by LocalGameEngine.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (ByteData? message) async =>
          const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  // ---------------------------------------------------------------------------
  // No undo available
  // ---------------------------------------------------------------------------

  group('no undo available', () {
    test('undo label starts as "No Action" and undo() is a no-op', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      expect(state.labelUndo, 'No Action');
      engine.undo();
      expect(state.labelUndo, 'No Action');
      expect(engine.phase, GamePhase.preGame);
    });

    test('calling undo twice only consumes action once', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam(); // undo: unstart jam
      engine.undo();     // consume
      engine.undo();     // second call – no action left

      // Should still be in lineup after the first undo (not crash or go further back)
      expect(engine.phase, GamePhase.lineup);
    });
  });

  // ---------------------------------------------------------------------------
  // unstartLineup – undo pressing "Stop Jam" from pre-game
  // ---------------------------------------------------------------------------

  group('undo unstartLineup', () {
    test('pressing Stop from pre-game starts lineup and sets undo label', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.stopJam(); // "Start Lineup" from pre-game
      expect(engine.phase, GamePhase.lineup);
      expect(state.labelUndo, 'UNDO: Unstart Lineup');
    });

    test('undo returns to preGame with clocks stopped', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.stopJam();
      engine.undo();

      expect(engine.phase, GamePhase.preGame);
      expect(state.clocks['Lineup']!.running, false);
      expect(state.clocks['Period']!.running, false);
      expect(state.labelUndo, 'No Action');
    });

    test('undo restores the period clock time if it was adjusted before lineup', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      // Operator adjusts period clock before starting lineup
      engine.adjustClock('Period', -5 * 60 * 1000); // subtract 5 min
      final adjustedTime = state.clocks['Period']!.time;

      engine.stopJam(); // start lineup
      engine.undo();    // go back to pre-game

      expect(state.clocks['Period']!.time, adjustedTime);
    });
  });

  // ---------------------------------------------------------------------------
  // unstartJam – undo pressing "Start Jam"
  // ---------------------------------------------------------------------------

  group('undo unstartJam', () {
    test('starting a jam sets undo label to Unstart Jam', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam();
      expect(state.labelUndo, 'UNDO: Unstart Jam');
    });

    test('undo restores lineup with period not running (first jam of game)', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      // Starting the first jam also starts the period for the first time.
      // Before period starts, Period clock is NOT running.
      engine.startJam();
      engine.undo();

      expect(engine.phase, GamePhase.lineup);
      expect(state.inJam, false);
      expect(state.clocks['Jam']!.running, false);
      expect(state.clocks['Lineup']!.running, true);
      // Period was not running before the first jam started
      expect(state.clocks['Period']!.running, false);
      expect(state.clocks['Jam']!.number, 0);
    });

    test('undo restores lineup with period running (subsequent jams)', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam(); // jam 1 – starts period
      engine.stopJam();  // stop → lineup (period still running)
      engine.startJam(); // jam 2
      expect(state.clocks['Jam']!.number, 2);

      engine.undo();

      expect(engine.phase, GamePhase.lineup);
      expect(state.clocks['Jam']!.number, 1);
      expect(state.clocks['Jam']!.running, false);
      expect(state.clocks['Lineup']!.running, true);
      expect(state.clocks['Period']!.running, true); // period was running during lineup
    });

    test('undo after start jam restores the lineup clock time', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam(); // jam 1
      engine.stopJam();  // lineup starts at 0
      // Advance lineup clock a bit (simulate time passing via adjustClock)
      engine.adjustClock('Lineup', 15 * 1000); // +15 s
      final lineupTime = state.clocks['Lineup']!.time;

      engine.startJam(); // jam 2
      engine.undo();

      expect(state.clocks['Lineup']!.time, lineupTime);
    });
  });

  // ---------------------------------------------------------------------------
  // unstopJam – undo pressing "Stop Jam" during a jam (normal, period not ended)
  // ---------------------------------------------------------------------------

  group('undo unstopJam (normal)', () {
    test('stopping a jam sets undo label to Unstop Jam', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam();
      engine.stopJam();
      expect(state.labelUndo, 'UNDO: Unstop Jam');
    });

    test('undo restores jam with period and jam clocks running', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam();
      engine.stopJam();
      engine.undo();

      expect(engine.phase, GamePhase.jam);
      expect(state.inJam, true);
      expect(state.clocks['Jam']!.running, true);
      expect(state.clocks['Period']!.running, true);
      expect(state.clocks['Lineup']!.running, false);
    });

    test('undo is a no-op when jam clock was already at 0 (would have expired)', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Jam', 0); // drain jam clock
      engine.stopJam();
      // labelUndo may be set, but undo() must reject since jam would have expired
      engine.undo();

      expect(engine.phase, isNot(GamePhase.jam));
    });

    test('starting a timeout during a jam saves an unstop jam undo', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam();
      engine.startTimeout(); // ends jam, starts timeout

      // startTimeout() calls _endJam() with fromExpiration=false, so undo is saved.
      // This lets the operator undo an accidental timeout call.
      expect(state.labelUndo, 'UNDO: Unstop Jam');
    });
  });

  // ---------------------------------------------------------------------------
  // unstopJam + period ended → intermission (non-final period)
  // ---------------------------------------------------------------------------

  group('undo unstopJam with period end → intermission', () {
    test('stopping jam when period has expired saves undo and ends period', () async {
      final (state, engine) = await _makeEngine(); // WFTDA: 2 periods
      addTearDown(engine.dispose);

      engine.startJam();                   // period 1, jam 1 running
      engine.setClockTime('Period', 0);    // period expires during jam
      engine.stopJam();                    // manually end jam → period ends → intermission

      expect(engine.phase, GamePhase.intermission);
      expect(state.clocks['Intermission']!.running, true);
      expect(state.labelUndo, 'UNDO: Unstop Jam');
    });

    test('undo reverses intermission and restores running jam', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam(); // → intermission

      engine.undo();

      expect(engine.phase, GamePhase.jam);
      expect(state.inJam, true);
      expect(state.clocks['Jam']!.running, true);
      expect(state.clocks['Lineup']!.running, false);
    });

    test('after undo, period clock stays at 0 and is not running', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam();
      engine.undo();

      expect(state.clocks['Period']!.time, 0);
      expect(state.clocks['Period']!.running, false);
    });

    test('after undo, intermission clock is reset to 0 and stopped', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam();
      engine.undo();

      expect(state.clocks['Intermission']!.running, false);
      expect(state.clocks['Intermission']!.time, 0);
    });

    test('after undo, stopping jam again ends the period (redo the period end)', () async {
      final (state, engine) = await _makeEngine();
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam(); // → intermission
      engine.undo();    // → back to jam
      engine.stopJam(); // → intermission again

      expect(engine.phase, GamePhase.intermission);
    });
  });

  // ---------------------------------------------------------------------------
  // unstopJam + period ended → game over (final period)
  // ---------------------------------------------------------------------------

  group('undo unstopJam with period end → game over', () {
    test('stopping jam when final period expires → unofficial score with undo available', () async {
      final (state, engine) = await _makeEngine(ruleset: _oneperiodRuleset());
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam(); // final period ends → unofficial score (operator must choose OT or end)

      expect(engine.phase, GamePhase.unofficialScore);
      expect(state.noMoreJam, true);
      expect(state.labelUndo, 'UNDO: Unstop Jam');
    });

    test('undo reverses game over and restores running jam', () async {
      final (state, engine) = await _makeEngine(ruleset: _oneperiodRuleset());
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam(); // → game over
      engine.undo();

      expect(engine.phase, GamePhase.jam);
      expect(state.inJam, true);
      expect(state.clocks['Jam']!.running, true);
      expect(state.noMoreJam, false);
      expect(state.connectionStatus, 'Offline Game');
    });

    test('after undo, period clock stays at 0 and is not running', () async {
      final (state, engine) = await _makeEngine(ruleset: _oneperiodRuleset());
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam();
      engine.undo();

      expect(state.clocks['Period']!.time, 0);
      expect(state.clocks['Period']!.running, false);
    });

    test('after undo, stopping jam again returns to unofficial score', () async {
      final (state, engine) = await _makeEngine(ruleset: _oneperiodRuleset());
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam(); // → unofficial score
      engine.undo();    // → back to jam
      engine.stopJam(); // → unofficial score again

      expect(engine.phase, GamePhase.unofficialScore);
      expect(state.noMoreJam, true);
    });
  });
}

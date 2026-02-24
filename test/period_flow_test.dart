import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roller_derby_jam_timer/models/game_config.dart';
import 'package:roller_derby_jam_timer/models/ruleset.dart';
import 'package:roller_derby_jam_timer/models/scoreboard_state.dart';
import 'package:roller_derby_jam_timer/services/local_game_engine.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<(ScoreboardState, LocalGameEngine)> _makeEngine(Ruleset ruleset) async {
  final state = ScoreboardState();
  final config = GameConfig(
    ruleset: ruleset,
    team1Name: 'Home',
    team2Name: 'Away',
  );
  final engine = LocalGameEngine(state, config);
  await engine.initialize();
  return (state, engine);
}

/// Plays one full period: starts jam, expires period clock, stops jam.
/// Leaves engine in intermission (or gameOver for final period).
void _expirePeriodDuringJam(LocalGameEngine engine) {
  engine.startJam();
  engine.setClockTime('Period', 0);
  engine.stopJam();
}

/// Skips intermission by starting a jam directly from intermission state.
void _skipIntermission(LocalGameEngine engine) {
  engine.startJam(); // from intermission → _endIntermission() → next period + lineup → jam
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (ByteData? message) async =>
          const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  // ---------------------------------------------------------------------------
  // Pre-game → first jam
  // ---------------------------------------------------------------------------

  group('starting the game', () {
    test('engine starts in preGame phase with period clock not running', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      expect(engine.phase, GamePhase.preGame);
      expect(state.clocks['Period']!.running, false);
      expect(state.clocks['Period']!.number, 0);
    });

    test('startJam from preGame starts period 1 and jam 1', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      engine.startJam();

      expect(engine.phase, GamePhase.jam);
      expect(state.clocks['Period']!.number, 1);
      expect(state.clocks['Jam']!.number, 1);
      expect(state.clocks['Period']!.running, true);
      expect(state.clocks['Jam']!.running, true);
      expect(state.inJam, true);
    });

    test('stopJam from preGame starts lineup without starting a jam', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      engine.stopJam(); // "Start Lineup" button

      expect(engine.phase, GamePhase.lineup);
      expect(state.clocks['Period']!.number, 1);
      expect(state.clocks['Jam']!.number, 0); // no jam yet
      expect(state.clocks['Lineup']!.running, true);
    });
  });

  // ---------------------------------------------------------------------------
  // Period expiration during a jam
  // ---------------------------------------------------------------------------

  group('period expiration', () {
    test('period ending during a jam transitions to intermission after jam stops', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setClockTime('Period', 0); // period expires while jam is running
      engine.stopJam();                 // jam ends → period ends → intermission

      expect(engine.phase, GamePhase.intermission);
      expect(state.clocks['Intermission']!.running, true);
      expect(state.clocks['Period']!.running, false);
      expect(state.clocks['Jam']!.running, false);
      expect(state.inJam, false);
    });

    test('intermission clock number matches the period that just ended', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      _expirePeriodDuringJam(engine);

      expect(state.clocks['Intermission']!.number, 1);
    });

    test('final period ending transitions to game over (not intermission)', () async {
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
      final (state, engine) = await _makeEngine(ruleset);
      addTearDown(engine.dispose);

      _expirePeriodDuringJam(engine);

      expect(engine.phase, GamePhase.gameOver);
      expect(state.noMoreJam, true);
      expect(state.connectionStatus, 'Game Over');
      expect(state.clocks['Intermission']!.running, false);
    });
  });

  // ---------------------------------------------------------------------------
  // Intermission → next period
  // ---------------------------------------------------------------------------

  group('intermission and period 2', () {
    test('startJam from intermission skips to next period lineup then jam', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      _expirePeriodDuringJam(engine); // → intermission after period 1
      _skipIntermission(engine);      // → starts period 2 + jam

      expect(engine.phase, GamePhase.jam);
      expect(state.clocks['Period']!.number, 2);
      expect(state.clocks['Intermission']!.running, false);
    });

    test('period 2 clock resets to full duration after intermission', () async {
      final ruleset = Ruleset.wftda();
      final (state, engine) = await _makeEngine(ruleset);
      addTearDown(engine.dispose);

      _expirePeriodDuringJam(engine);
      _skipIntermission(engine);

      // Period 2 should start at full duration
      expect(state.clocks['Period']!.time, ruleset.periodDurationMs);
    });

    test('WFTDA jams reset at the start of each period', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      // 3 jams in period 1
      engine.startJam(); engine.stopJam();
      engine.startJam(); engine.stopJam();
      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam(); // period 1 ends after jam 3

      _skipIntermission(engine); // start period 2, jam counter resets to 1
      expect(state.clocks['Jam']!.number, 1);
    });

    test('RDCL jams continue across periods (no reset)', () async {
      final (state, engine) = await _makeEngine(Ruleset.rdcl());
      addTearDown(engine.dispose);

      // 3 jams in period 1
      engine.startJam(); engine.stopJam();
      engine.startJam(); engine.stopJam();
      engine.startJam();
      engine.setClockTime('Period', 0);
      engine.stopJam(); // period 1 ends after jam 3

      _skipIntermission(engine); // start period 2, jam continues at 4
      expect(state.clocks['Jam']!.number, 4);
    });
  });

  // ---------------------------------------------------------------------------
  // Full 2-period WFTDA game
  // ---------------------------------------------------------------------------

  group('full 2-period game', () {
    test('plays through to game over after 2 periods', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      // Period 1
      _expirePeriodDuringJam(engine);
      expect(engine.phase, GamePhase.intermission);

      // Period 2
      _skipIntermission(engine);
      engine.setClockTime('Period', 0);
      engine.stopJam(); // end period 2 → game over

      expect(engine.phase, GamePhase.gameOver);
      expect(state.noMoreJam, true);
    });

    test('game over clears all running clocks', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      _expirePeriodDuringJam(engine);
      _skipIntermission(engine);
      engine.setClockTime('Period', 0);
      engine.stopJam();

      expect(state.clocks['Jam']!.running, false);
      expect(state.clocks['Period']!.running, false);
      expect(state.clocks['Lineup']!.running, false);
      expect(state.clocks['Intermission']!.running, false);
      expect(state.inJam, false);
    });
  });

  // ---------------------------------------------------------------------------
  // Official reviews reset between periods
  // ---------------------------------------------------------------------------

  group('official review resets', () {
    test('reviews reset to ruleset default at the start of each period', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      // WFTDA gives 1 review per period
      expect(state.team1.officialReviews, 1);

      // Use up team 1's review via a timeout
      engine.startJam();
      engine.setTimeoutOwner('1', isOfficialReview: true); // ends jam, starts timeout
      expect(state.team1.officialReviews, 0);

      // Return from timeout to lineup, then start another jam to end the period
      engine.endTimeout();
      engine.setClockTime('Period', 0); // expire period clock while in lineup
      engine.startJam();  // period clock starts running at 0
      engine.stopJam();   // _endJam sees period.time = 0 → period 1 ends → intermission

      expect(engine.phase, GamePhase.intermission);

      // Start period 2 via intermission
      _skipIntermission(engine); // → _endIntermission → _startPeriod(2) resets reviews

      // Reviews should be restored for period 2
      expect(state.team1.officialReviews, 1);
      expect(state.team2.officialReviews, 1);
    });

    test('retained reviews are cleared at the start of a new period', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      engine.startJam();
      engine.setRetainedReview(1, true);
      expect(state.team1.retainedOfficialReview, true);

      engine.setClockTime('Period', 0);
      engine.stopJam();
      _skipIntermission(engine);

      expect(state.team1.retainedOfficialReview, false);
    });
  });

  // ---------------------------------------------------------------------------
  // Jam numbering within a period
  // ---------------------------------------------------------------------------

  group('jam numbering', () {
    test('jam number increments on each startJam call', () async {
      final (state, engine) = await _makeEngine(Ruleset.wftda());
      addTearDown(engine.dispose);

      engine.startJam();
      expect(state.clocks['Jam']!.number, 1);
      engine.stopJam();

      engine.startJam();
      expect(state.clocks['Jam']!.number, 2);
      engine.stopJam();

      engine.startJam();
      expect(state.clocks['Jam']!.number, 3);
    });

    test('jam clock resets to full duration on each startJam', () async {
      final ruleset = Ruleset.wftda();
      final (state, engine) = await _makeEngine(ruleset);
      addTearDown(engine.dispose);

      engine.startJam();
      engine.adjustClock('Jam', -30 * 1000); // consume 30s
      engine.stopJam();
      engine.startJam();

      expect(state.clocks['Jam']!.time, ruleset.jamDurationMs);
    });
  });
}

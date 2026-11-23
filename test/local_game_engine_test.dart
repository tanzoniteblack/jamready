import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jam_ready/models/game_config.dart';
import 'package:jam_ready/models/ruleset.dart';
import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/services/local_game_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScoreboardState state;
  late LocalGameEngine engine;

  setUpAll(() {
    // Mock the Pigeon-based wakelock_plus API
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle'),
      (MethodCall methodCall) async {
        return null;
      },
    );
    // Also mock the pigeon message channel directly via binary messenger
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (ByteData? message) async {
        // Return an empty encoded response
        return const StandardMessageCodec().encodeMessage(<Object?>[null]);
      },
    );
  });

  setUp(() {
    state = ScoreboardState();
  });

  tearDown(() async {
    try {
      await engine.dispose();
    } catch (_) {
      // Ignore dispose errors in tests
    }
  });

  group('LocalGameEngine initialization', () {
    test('initializes with WFTDA ruleset defaults', () async {
      final config = GameConfig(
        ruleset: Ruleset.wftda(),
        team1Name: 'Team A',
        team2Name: 'Team B',
      );
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      expect(state.team1.name, 'Team A');
      expect(state.team2.name, 'Team B');
      expect(state.team1.score, 0);
      expect(state.team2.score, 0);
      expect(state.team1.timeouts, 3);
      expect(state.team1.officialReviews, 1);
      expect(state.connectionStatus, 'Offline Game');
      expect(engine.isLocal, true);
      expect(engine.supportsUndo, true);
    });

    test('initializes with RDCL ruleset defaults', () async {
      final config = GameConfig(
        ruleset: Ruleset.rdcl(),
        team1Name: 'Salt',
        team2Name: 'Pepper',
      );
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      expect(state.team1.name, 'Salt');
      expect(state.team2.name, 'Pepper');
      expect(state.team1.colorBg, 'F2F2F2');
      expect(state.team1.colorFg, '1A1A1A');
      expect(state.team2.colorBg, '2E2E2E');
      expect(state.team2.colorFg, 'F5F5F5');
      expect(state.lineupDuration, 30000);
      expect(state.clocks['Jam']!.time, 60000); // RDCL: 1 min jams
      expect(state.clocks['Period']!.time, 15 * 60 * 1000); // RDCL: 15 min periods
    });
  });

  group('LocalGameEngine clock accuracy', () {
    test('running clocks track elapsed time without drift', () {
      fakeAsync((async) {
        engine = LocalGameEngine(
          state,
          GameConfig(
            ruleset: Ruleset.wftda(),
            team1Name: 'Team A',
            team2Name: 'Team B',
          ),
        );
        engine.initialize();
        async.flushMicrotasks();

        engine.stopJam(); // preGame -> lineup
        engine.startJam(); // lineup -> jam, period clock starts
        async.elapse(const Duration(seconds: 90));

        expect(state.clocks['Jam']!.time, 30 * 1000);
        expect(state.clocks['Period']!.time, (30 * 60 - 90) * 1000);

        engine.dispose();
      });
    });
  });

  group('LocalGameEngine clock timing', () {
    const step = Duration(milliseconds: 16);
    const stepMs = 16; // tick interval: timing assertions allow one tick
    const periodMs = 30 * 60 * 1000;

    void startEngine(FakeAsync async) {
      engine = LocalGameEngine(
        state,
        GameConfig(
          ruleset: Ruleset.wftda(),
          team1Name: 'Team A',
          team2Name: 'Team B',
        ),
      );
      engine.initialize();
      async.flushMicrotasks();
    }

    /// Steps time forward until [done] is true; returns elapsed ms.
    int elapseUntil(FakeAsync async, bool Function() done) {
      var ms = 0;
      while (!done()) {
        async.elapse(step);
        ms += stepMs;
      }
      return ms;
    }

    Duration ms(int milliseconds) => Duration(milliseconds: milliseconds);

    // Starting part-way through a second must not change how long the first
    // second is displayed, nor the jam's length.
    for (final phaseMs in [300, 700]) {
      test('jam started ${phaseMs}ms into a second runs exactly 2:00', () {
        fakeAsync((async) {
          startEngine(async);
          engine.stopJam(); // preGame -> lineup
          engine.startJam(); // first jam starts the period clock
          async.elapse(const Duration(seconds: 10));
          engine.stopJam();

          async.elapse(ms(20000 + phaseMs));
          engine.startJam();

          final jam = state.clocks['Jam']!;
          final untilFirstTick = elapseUntil(async, () => jam.time != 120000);
          expect(untilFirstTick, inInclusiveRange(1000 - stepMs, 1000 + stepMs));
          expect(jam.time, 119000);

          final rest = elapseUntil(async, () => engine.phase != GamePhase.jam);
          expect(untilFirstTick + rest,
              inInclusiveRange(120000 - 2 * stepMs, 120000 + stepMs));

          // The lineup started on expiry also shows 0 for a full second.
          final lineup = state.clocks['Lineup']!;
          final untilLineupTick = elapseUntil(async, () => lineup.time != 0);
          expect(untilLineupTick, inInclusiveRange(1000 - stepMs, 1000 + stepMs));

          engine.dispose();
        });
      });
    }

    test('undoing the first jam restores the period clock and keeps lineup',
        () {
      fakeAsync((async) {
        startEngine(async);
        engine.stopJam(); // preGame -> lineup
        async.elapse(const Duration(seconds: 10));
        engine.startJam();
        async.elapse(const Duration(seconds: 5));

        engine.undo();

        expect(engine.phase, GamePhase.lineup);
        expect(state.clocks['Period']!.running, false);
        expect(state.clocks['Period']!.time, periodMs);
        // Lineup carries on as though the jam never started.
        expect(state.clocks['Lineup']!.running, true);
        expect(state.clocks['Lineup']!.time, 15000);

        async.elapse(const Duration(seconds: 2));
        expect(state.clocks['Period']!.time, periodMs);
        expect(state.clocks['Lineup']!.time, 17000);

        engine.dispose();
      });
    });

    test('undoing a later jam start keeps lineup and period running', () {
      fakeAsync((async) {
        startEngine(async);
        engine.stopJam();
        engine.startJam();
        async.elapse(const Duration(seconds: 10));
        engine.stopJam(); // lineup, period at 29:50
        async.elapse(const Duration(seconds: 20));
        engine.startJam();
        // 34s total lands on a 16ms tick, so the period display is current.
        async.elapse(const Duration(seconds: 4));

        engine.undo();

        expect(engine.phase, GamePhase.lineup);
        expect(state.clocks['Lineup']!.time, 24000);
        expect(state.clocks['Period']!.running, true);
        expect(state.clocks['Period']!.time, periodMs - 34000);

        engine.dispose();
      });
    });

    test('undoing a jam stop during a timeout restores lost period time', () {
      fakeAsync((async) {
        startEngine(async);
        engine.stopJam();
        engine.startJam();
        async.elapse(const Duration(seconds: 10));
        engine.stopJam(); // period at 29:50
        async.elapse(const Duration(seconds: 2));
        engine.startTimeout(); // stops the period clock
        async.elapse(const Duration(seconds: 3));

        engine.undo();

        expect(engine.phase, GamePhase.jam);
        expect(state.clocks['Jam']!.time, 120000 - 15000);
        expect(state.clocks['Period']!.running, true);
        expect(state.clocks['Period']!.time, periodMs - 15000);

        engine.dispose();
      });
    });
  });

  group('LocalGameEngine game flow', () {
    test('starts lineup when stopJam called in pre-game', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      expect(engine.phase, GamePhase.preGame);
      expect(state.clocks['Period']!.number, 0);

      engine.stopJam(); // "Start Lineup" action

      expect(engine.phase, GamePhase.lineup);
      expect(state.clocks['Period']!.number, 1);
      expect(state.clocks['Lineup']!.running, true);
    });

    test('starts jam from lineup', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      engine.stopJam(); // Start lineup
      expect(engine.phase, GamePhase.lineup);

      engine.startJam();

      expect(engine.phase, GamePhase.jam);
      expect(state.inJam, true);
      expect(state.clocks['Jam']!.running, true);
      expect(state.clocks['Jam']!.number, 1);
      expect(state.clocks['Period']!.running, true);
      expect(state.clocks['Lineup']!.running, false);
    });

    test('stops jam and returns to lineup', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      engine.stopJam(); // Start lineup
      engine.startJam();
      expect(engine.phase, GamePhase.jam);

      engine.stopJam();

      expect(engine.phase, GamePhase.lineup);
      expect(state.inJam, false);
      expect(state.clocks['Jam']!.running, false);
      expect(state.clocks['Lineup']!.running, true);
      expect(state.clocks['Lineup']!.time, 0); // Reset to 0
    });
  });

  group('LocalGameEngine timeout handling', () {
    test('starts timeout with official timeout as default', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      engine.stopJam(); // Start lineup
      engine.startTimeout();

      expect(engine.phase, GamePhase.timeout);
      expect(state.clocks['Timeout']!.running, true);
      expect(state.clocks['Lineup']!.running, false);
      expect(state.timeoutOwner, 'O');
      expect(state.labelStop, 'End Timeout');
    });

    test('sets team timeout and decrements count', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      expect(state.team1.timeouts, 3);

      engine.stopJam();
      engine.setTimeoutOwner('1');

      expect(state.timeoutOwner, '1');
      expect(state.team1.timeouts, 2);
      expect(state.officialReview, 'false');
    });

    test('sets official review and decrements count', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      expect(state.team2.officialReviews, 1);

      engine.stopJam();
      engine.setTimeoutOwner('2', isOfficialReview: true);

      expect(state.timeoutOwner, '2');
      expect(state.team2.officialReviews, 0);
      expect(state.officialReview, 'true');
    });

    test('end timeout returns to lineup', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      engine.stopJam();
      engine.startTimeout();
      expect(engine.phase, GamePhase.timeout);

      engine.endTimeout();

      expect(engine.phase, GamePhase.lineup);
      expect(state.clocks['Timeout']!.running, false);
      expect(state.clocks['Lineup']!.running, true);
      expect(state.timeoutOwner, '');
    });
  });

  group('LocalGameEngine score adjustment', () {
    test('adjusts team 1 score', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      expect(state.team1.score, 0);

      engine.adjustScore(1, 5);
      expect(state.team1.score, 5);

      engine.adjustScore(1, -2);
      expect(state.team1.score, 3);
    });

    test('score cannot go below zero', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      engine.adjustScore(2, 3);
      expect(state.team2.score, 3);

      engine.adjustScore(2, -10);
      expect(state.team2.score, 0);
    });
  });

  group('LocalGameEngine clock adjustment', () {
    test('adjusts jam clock', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      final initialTime = state.clocks['Jam']!.time;

      engine.adjustClock('Jam', -5000);
      expect(state.clocks['Jam']!.time, initialTime - 5000);

      engine.adjustClock('Jam', 2000);
      expect(state.clocks['Jam']!.time, initialTime - 3000);
    });

    test('clock time cannot go below zero', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      engine.adjustClock('Jam', -999999);
      expect(state.clocks['Jam']!.time, 0);
    });
  });

  group('LocalGameEngine retained review', () {
    test('sets retained review and restores count', () async {
      final config = GameConfig(ruleset: Ruleset.wftda());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      // Use the review first
      engine.stopJam();
      engine.setTimeoutOwner('1', isOfficialReview: true);
      expect(state.team1.officialReviews, 0);

      engine.endTimeout();

      // Retain the review
      engine.setRetainedReview(1, true);
      expect(state.team1.retainedOfficialReview, true);
      expect(state.team1.officialReviews, 1);
    });
  });

  group('RDCL ruleset specifics', () {
    test('RDCL has 4 periods and 1-minute jams', () async {
      final config = GameConfig(ruleset: Ruleset.rdcl());
      engine = LocalGameEngine(state, config);
      await engine.initialize();

      expect(engine.ruleset.periodCount, 4);
      expect(engine.ruleset.jamDurationMs, 60000);
      expect(engine.ruleset.jamsResetPerPeriod, false);
    });
  });
}

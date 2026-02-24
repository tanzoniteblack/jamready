import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roller_derby_jam_timer/models/game_config.dart';
import 'package:roller_derby_jam_timer/models/ruleset.dart';
import 'package:roller_derby_jam_timer/models/scoreboard_state.dart';
import 'package:roller_derby_jam_timer/services/local_game_engine.dart';

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
      expect(engine.supportsUndo, false);
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
      expect(state.lineupDuration, 30000);
      expect(state.clocks['Jam']!.time, 60000); // RDCL: 1 min jams
      expect(state.clocks['Period']!.time, 15 * 60 * 1000); // RDCL: 15 min periods
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

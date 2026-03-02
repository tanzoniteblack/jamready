import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/screens/jam_timer_screen.dart';
import 'package:jam_ready/services/game_engine.dart';

class _FakeRemoteEngine implements GameEngine {
  _FakeRemoteEngine(this._state);

  final ScoreboardState _state;

  @override
  bool get isActive => true;

  @override
  bool get isLocal => false;

  @override
  bool get supportsUndo => true;

  @override
  ScoreboardState get state => _state;

  @override
  Future<void> dispose() async {}

  @override
  Future<void> initialize() async {}

  @override
  void adjustClock(String clockName, int deltaMs) {}

  @override
  void adjustScore(int teamNumber, int delta) {}

  @override
  void endTimeout() {}

  @override
  void setClockTime(String clockName, int timeMs) {}

  @override
  void setRetainedReview(int teamNumber, bool retained) {}

  @override
  void setTimeoutOwner(String owner, {bool isOfficialReview = false}) {}

  @override
  void startJam() {}

  @override
  void startTimeout() {}

  @override
  void stopJam() {}

  @override
  void undo() {}

  @override
  void endGame() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vibrationChannel = MethodChannel('vibration');
  final List<MethodCall> vibrationCalls = <MethodCall>[];

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vibrationChannel, (MethodCall methodCall) async {
      vibrationCalls.add(methodCall);
      return null;
    });
  });

  setUp(() {
    vibrationCalls.clear();
  });

  Widget buildHarness(ScoreboardState state) {
    final engine = _FakeRemoteEngine(state);
    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: state)],
      child: MaterialApp(home: JamTimerScreen(engine: engine)),
    );
  }

  /// Loads a fixture JSON file and feeds it through the same [ScoreboardState]
  /// parsing path that [RemoteGameEngine] uses when receiving server messages.
  ScoreboardState stateFromFixture(String filename) {
    final file = File('test/fixtures/$filename');
    final Map<String, dynamic> data = jsonDecode(file.readAsStringSync());
    final state = ScoreboardState();
    state.updateFromMap(data);
    state.setConnectionStatus('Connected');
    return state;
  }

  testWidgets('timeout state does not fall through to READY in remote mode', (
    tester,
  ) async {
    final state = ScoreboardState();
    state.setConnectionStatus('Connected');
    state.clocks['Period']!.number = 0;
    state.clocks['Timeout']!.displayName = 'Timeout';
    state.clocks['Timeout']!.time = 15000;
    state.clocks['Timeout']!.running = true;
    state.timeoutOwner = 'O';

    await tester.pumpWidget(buildHarness(state));
    await tester.pump();

    expect(find.text('READY'), findsNothing);
    expect(find.text('OFFICIAL TIMEOUT'), findsOneWidget);
  });

  testWidgets(
    'intermission running during active jam does not show pre-period slider',
    (tester) async {
      final state = ScoreboardState();
      state.setConnectionStatus('Connected');
      state.inJam = true;
      state.clocks['Jam']!.displayName = 'Jam';
      state.clocks['Jam']!.time = 0;
      state.clocks['Jam']!.running = false;
      state.clocks['Intermission']!.running = true;
      state.clocks['Intermission']!.time = 60000;
      state.labelStop = 'Stop Jam';

      await tester.pumpWidget(buildHarness(state));
      await tester.pump();

      expect(find.text('STOP JAM'), findsOneWidget);
      expect(find.text('SLIDE TO START LINEUP'), findsNothing);
    },
  );

  testWidgets(
    'unofficial score (noMoreJam fallback) shows unofficial display not intermission clock',
    (tester) async {
      // When periodCount is unknown, noMoreJam=true is the fallback signal
      // for the post-game intermission → should show UNOFFICIAL SCORE.
      final state = ScoreboardState();
      state.setConnectionStatus('Connected');
      state.noMoreJam = true;
      state.clocks['Intermission']!.running = true;
      state.clocks['Intermission']!.time = 300000;
      state.clocks['Intermission']!.displayName = 'Intermission';
      state.clocks['Intermission']!.number = 2;

      await tester.pumpWidget(buildHarness(state));
      await tester.pump();

      expect(find.text('UNOFFICIAL'), findsOneWidget);
      expect(find.text('SCORE'), findsOneWidget);
      expect(find.text('GAME OVER'), findsNothing);
      expect(find.text('READY'), findsNothing);
    },
  );

  testWidgets('pregame does not show "PERIOD 0" in remote header row', (
    tester,
  ) async {
    final state = ScoreboardState();
    state.setConnectionStatus('Connected');
    state.clocks['Period']!.displayName = 'Period';
    state.clocks['Period']!.number = 0;
    state.clocks['Period']!.time = 1800000;
    state.clocks['Period']!.running = false;

    await tester.pumpWidget(buildHarness(state));
    await tester.pump();

    expect(find.text('PERIOD 0'), findsNothing);
  });

  testWidgets('second-lineup overlap shows lineup clock as active', (
    tester,
  ) async {
    final state = ScoreboardState();
    state.setConnectionStatus('Connected');
    state.clocks['Lineup']!.displayName = 'Lineup';
    state.clocks['Lineup']!.time = 20000;
    state.clocks['Lineup']!.running = true;
    state.clocks['Timeout']!.displayName = 'Timeout';
    state.clocks['Timeout']!.time = 50000;
    state.clocks['Timeout']!.running = true;
    state.timeoutOwner = 'O';

    await tester.pumpWidget(buildHarness(state));
    await tester.pump();

    expect(find.text('LINEUP'), findsOneWidget);
    expect(find.text('0:20'), findsOneWidget);
    expect(find.text('0:50'), findsNothing);
  });

  testWidgets('team-owned timeout vibrates at 50s, 55s, and 60s only', (
    tester,
  ) async {
    final state = ScoreboardState();
    state.setConnectionStatus('Connected');
    state.team1.serverId = 'team-1-id';
    state.timeoutOwner = 'team-1-id';
    state.officialReview = 'false';
    state.clocks['Timeout']!.running = true;
    state.clocks['Timeout']!.time = 49000;

    await tester.pumpWidget(buildHarness(state));
    await tester.pump();
    expect(vibrationCalls, isEmpty);

    state.clocks['Timeout']!.time = 50000;
    state.notify();
    await tester.pump();

    state.clocks['Timeout']!.time = 55000;
    state.notify();
    await tester.pump();

    state.clocks['Timeout']!.time = 60000;
    state.notify();
    await tester.pump();

    expect(
      vibrationCalls.where((call) => call.method == 'vibrate').length,
      3,
    );
  });

  testWidgets(
    'post-countdown READY state shows READY text and slide to start lineup',
    (tester) async {
      final state = stateFromFixture('pre-game-no-time-to-derby.json');

      await tester.pumpWidget(buildHarness(state));
      await tester.pump();

      expect(find.text('READY'), findsOneWidget);
      expect(find.text('SLIDE TO START LINEUP'), findsOneWidget);
      expect(find.text('TIME TO DERBY'), findsNothing);
      expect(find.text('GAME OVER'), findsNothing);
    },
  );

  testWidgets(
    'pre-game countdown shows TIME TO DERBY and slide to start lineup',
    (tester) async {
      final state = stateFromFixture('pre-game-time-to-derby.json');

      await tester.pumpWidget(buildHarness(state));
      await tester.pump();

      expect(find.text('TIME TO DERBY'), findsOneWidget);
      expect(find.text('SLIDE TO START LINEUP'), findsOneWidget);
      expect(find.text('READY'), findsNothing);
      expect(find.text('GAME OVER'), findsNothing);
    },
  );

  testWidgets(
    'unofficial score (tied game, overtime possible) shows unofficial display not intermission',
    (tester) async {
      final state = stateFromFixture('unofficial-score-overtime-possible.json');

      await tester.pumpWidget(buildHarness(state));
      await tester.pump();

      expect(find.text('UNOFFICIAL'), findsOneWidget);
      expect(find.text('SCORE'), findsOneWidget);
      // Controls must be live so overtime can be triggered.
      expect(find.text('GAME OVER'), findsNothing);
    },
  );

  testWidgets('officialScore shows game over regardless of other state', (
    tester,
  ) async {
    final state = ScoreboardState();
    state.setConnectionStatus('Connected');
    state.officialScore = true;
    // No other game-over signals set — officialScore alone is sufficient.

    await tester.pumpWidget(buildHarness(state));
    await tester.pump();

    expect(find.text('GAME OVER'), findsOneWidget);
  });

  testWidgets(
    'periodCount distinguishes halftime from game over when noMoreJam is true',
    (tester) async {
      // 2-period game, halftime: Intermission.Number(1) < periodCount(2)
      final state = ScoreboardState();
      state.setConnectionStatus('Connected');
      state.periodCount = 2;
      state.noMoreJam = true;
      state.clocks['Intermission']!.number = 1;
      state.clocks['Intermission']!.running = true;
      state.clocks['Intermission']!.time = 600000;

      await tester.pumpWidget(buildHarness(state));
      await tester.pump();

      expect(find.text('GAME OVER'), findsNothing);
      // Controls are locked during active intermission clock.
      expect(find.text('SLIDE TO START LINEUP'), findsNothing);
    },
  );

  testWidgets(
    'periodCount shows unofficial score when intermission number reaches period count',
    (tester) async {
      // 2-period game, post-game: Intermission.Number(2) == periodCount(2)
      // → unofficial score, not GAME OVER (that requires officialScore=true)
      final state = ScoreboardState();
      state.setConnectionStatus('Connected');
      state.periodCount = 2;
      state.noMoreJam = true;
      state.clocks['Intermission']!.number = 2;
      state.clocks['Intermission']!.running = false;
      state.clocks['Intermission']!.time = 0;

      await tester.pumpWidget(buildHarness(state));
      await tester.pump();

      expect(find.text('UNOFFICIAL'), findsOneWidget);
      expect(find.text('SCORE'), findsOneWidget);
      expect(find.text('GAME OVER'), findsNothing);
    },
  );

  testWidgets(
    'between-period lineup with noMoreJam shows lineup clock not game over',
    (tester) async {
      final state = stateFromFixture('between-period-lineup.json');

      await tester.pumpWidget(buildHarness(state));
      await tester.pump();

      expect(find.text('GAME OVER'), findsNothing);
      expect(find.text('LINEUP'), findsOneWidget);
    },
  );

  testWidgets(
    'running jam at end of period shows jam clock and stop jam button',
    (tester) async {
      final state = stateFromFixture('end-of-period-1-running-jam.json');

      await tester.pumpWidget(buildHarness(state));
      await tester.pump();

      expect(find.text('STOP JAM'), findsOneWidget);
      expect(find.text('SLIDE TO START LINEUP'), findsNothing);
    },
  );

  testWidgets(
    'halftime intermission locks out controls until clock ends',
    (tester) async {
      final state = stateFromFixture('end-of-period-1.json');

      await tester.pumpWidget(buildHarness(state));
      await tester.pump();

      // Slider must not appear while intermission is still running.
      expect(find.text('SLIDE TO START LINEUP'), findsNothing);
      // Start button is rendered but disabled (controls locked out).
      expect(find.text('START JAM'), findsOneWidget);
      expect(find.text('GAME OVER'), findsNothing);
      expect(find.text('READY'), findsNothing);
    },
  );

  testWidgets('official and unlabeled timeouts do not trigger threshold haptics', (
    tester,
  ) async {
    final state = ScoreboardState();
    state.setConnectionStatus('Connected');
    state.team1.serverId = 'team-1-id';
    state.clocks['Timeout']!.running = true;
    state.clocks['Timeout']!.time = 60000;

    await tester.pumpWidget(buildHarness(state));
    await tester.pump();

    state.timeoutOwner = 'O';
    state.officialReview = 'false';
    state.notify();
    await tester.pump();

    state.timeoutOwner = '';
    state.officialReview = 'false';
    state.notify();
    await tester.pump();

    expect(vibrationCalls.where((call) => call.method == 'vibrate'), isEmpty);
  });
}

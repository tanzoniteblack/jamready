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

  testWidgets('game over shows final state instead of intermission clock', (
    tester,
  ) async {
    final state = ScoreboardState();
    state.setConnectionStatus('Connected');
    state.noMoreJam = true;
    state.clocks['Intermission']!.running = true;
    state.clocks['Intermission']!.time = 300000;
    state.clocks['Intermission']!.displayName = 'Intermission';
    state.clocks['Intermission']!.number = 2;

    await tester.pumpWidget(buildHarness(state));
    await tester.pump();

    expect(find.text('GAME OVER'), findsOneWidget);
    expect(find.text('READY'), findsNothing);
  });

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

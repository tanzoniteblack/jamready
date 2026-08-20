import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jam_ready/models/penalty_box_state.dart';
import 'package:jam_ready/models/skater_seat.dart';
import 'package:jam_ready/services/remote_penalty_engine.dart';

import '../test_helpers.dart';

typedef EngineFixture = ({
  RemotePenaltyEngine engine,
  FakeWebSocketChannel channel,
  PenaltyBoxState state,
});

Future<EngineFixture> setupEngine() async {
  final channel = FakeWebSocketChannel();
  final state = makeState();
  final engine = RemotePenaltyEngine(
    state,
    channelFactory: (_) => channel,
    wakelockEnable: () {},
    wakelockDisable: () {},
  );
  await engine.connect('http://localhost:8000');
  await Future.microtask(() {});
  return (engine: engine, channel: channel, state: state);
}

Future<void> sendAndPump(
  FakeWebSocketChannel channel,
  Map<String, dynamic> message,
) async {
  channel.send(message);
  await Future.microtask(() {});
  await Future.microtask(() {});
}

void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('remote game state', () {
    test('a new game clears local timers and replaces game data', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Game': 'game-one',
        'ScoreBoard.CurrentGame.Team(1).Name': 'Salt',
        'ScoreBoard.CurrentGame.Team(1).Skater(old).RosterNumber': '10',
      });
      state.seatSkater(
        seat: state.team1Jammer,
        number: '10',
        position: SkaterPosition.jammer,
      );
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Game': 'game-two',
        'ScoreBoard.CurrentGame.Team(1).Name': 'Black',
        'ScoreBoard.CurrentGame.Team(1).Skater(new).RosterNumber': '42',
      });

      expect(
        state.seats,
        everyElement(predicate<SkaterSeat>((s) => s.isEmpty)),
      );
      expect(state.team1.name, 'Black');
      expect(state.lookupSkaterId(1, '10'), isNull);
      expect(state.lookupSkaterId(1, '42'), 'new');
      await engine.dispose();
    });

    test('remote jam boundaries control local timers', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {'ScoreBoard.CurrentGame.InJam': false});
      state.seatSkater(
        seat: state.team1Blocker1,
        number: '22',
        position: SkaterPosition.blocker,
      );
      expect(state.team1Blocker1.isRunning, isFalse);

      await sendAndPump(channel, {'ScoreBoard.CurrentGame.InJam': true});
      expect(state.team1Blocker1.isRunning, isTrue);
      await sendAndPump(channel, {'ScoreBoard.CurrentGame.InJam': false});
      expect(state.team1Blocker1.isRunning, isFalse);
      await engine.dispose();
    });

    test('updates mainstream metadata and rosters', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Clock(Jam).Number': 5,
        'ScoreBoard.CurrentGame.Clock(Period).Number': 2,
        'ScoreBoard.CurrentGame.Team(1).Color(operator.fg)': '#FF0000',
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-123).RosterNumber': '42',
        'Game.Team(2).Skater': {
          'uuid-a': {'RosterNumber': '10'},
        },
      });

      expect(state.jamNumber, 5);
      expect(state.periodNumber, 2);
      expect(state.team1.color.toARGB32(), 0xFFFF0000);
      expect(state.lookupSkaterId(1, '42'), 'uuid-123');
      expect(state.lookupSkaterId(2, '10'), 'uuid-a');
      await engine.dispose();
    });
  });

  testWidgets('local timers continue after the server disconnects', (
    tester,
  ) async {
    final channel = FakeWebSocketChannel();
    final state = makeState();
    final engine = RemotePenaltyEngine(
      state,
      channelFactory: (_) => channel,
      wakelockEnable: () {},
      wakelockDisable: () {},
      localClock: () => tester.binding.clock.now(),
    );
    await engine.connect('http://localhost:8000');
    await tester.pump();
    state.seatSkater(
      seat: state.team1Blocker1,
      number: '22',
      position: SkaterPosition.blocker,
    );
    final before = state.team1Blocker1.timeRemaining;
    channel.dispose();
    await tester.pump(const Duration(seconds: 1));

    expect(state.team1Blocker1.timeRemaining, lessThan(before));
    expect(engine.isLocal, isTrue);

    engine.toggleJam();
    expect(state.jamRunning, isFalse);
    expect(state.team1Blocker1.isRunning, isFalse);

    engine.toggleJam();
    expect(state.jamRunning, isTrue);
    expect(state.team1Blocker1.isRunning, isTrue);
    await engine.dispose();
  });

  test('reports a known skater', () async {
    final (:engine, :channel, :state) = await setupEngine();
    state.updateRoster(1, '42', 'uuid-abc');
    engine.reportPenalty(
      teamIndex: 1,
      skaterNumber: '42',
      periodNumber: 2,
      jamNumber: 7,
    );
    await Future.microtask(() {});

    final penalties = channel.sentWithAction('Penalty');
    expect(penalties, hasLength(1));
    expect((penalties.single['data'] as Map)['skaterId'], 'uuid-abc');
    await engine.dispose();
  });
}

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jam_ready/models/penalty_box_state.dart';
import 'package:jam_ready/models/skater_seat.dart';
import 'package:jam_ready/services/remote_penalty_engine.dart';
import 'package:flutter/widgets.dart';

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

    test('the jam clock running out does not end the jam', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.InJam': true,
        'ScoreBoard.CurrentGame.Clock(Jam).Running': true,
      });
      state.seatSkater(
        seat: state.team1Blocker1,
        number: '22',
        position: SkaterPosition.blocker,
      );
      expect(state.team1Blocker1.isRunning, isTrue);

      // At 2:00 CRG stops the jam clock, but without auto-end the jam goes on
      // until it is called.
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Clock(Jam).Running': false,
      });
      expect(state.jamRunning, isTrue);
      expect(state.team1Blocker1.isRunning, isTrue);

      await sendAndPump(channel, {'ScoreBoard.CurrentGame.InJam': false});
      expect(state.jamRunning, isFalse);
      expect(state.team1Blocker1.isRunning, isFalse);
      await engine.dispose();
    });

    test('the jam clock drives jams for a scoreboard without InJam', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Clock(Jam).Running': true,
      });
      expect(state.jamRunning, isTrue);
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Clock(Jam).Running': false,
      });
      expect(state.jamRunning, isFalse);
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

  group('jammer role', () {
    test('auto-fills a jammer timer without seating the jammer', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-123).RosterNumber': '42',
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-123).Role': 'Jammer',
      });

      expect(state.team1Jammer.isOccupied, isFalse);
      state.startSeatAnonymously(state.team1Jammer);
      expect(state.team1Jammer.skaterNumber, '42');
      await engine.dispose();
    });

    test('a jammer change does not affect the running jammer seat', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-a).RosterNumber': '42',
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-b).RosterNumber': '77',
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-a).Role': 'Jammer',
        'ScoreBoard.CurrentGame.InJam': true,
      });
      state.startSeatAnonymously(state.team1Jammer);
      expect(state.team1Jammer.skaterNumber, '42');
      expect(state.team1Jammer.isRunning, isTrue);

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-a).Role': 'Blocker',
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-b).Role': 'Jammer',
      });

      expect(state.jammerNumber(1), '77');
      expect(state.team1Jammer.skaterNumber, '42');
      expect(state.team1Jammer.isRunning, isTrue);
      expect(state.team1Jammer.penaltyCount, 1);
      await engine.dispose();
    });

    test('is forgotten when the scoreboard benches the jammer', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-a).RosterNumber': '42',
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-a).Role': 'Jammer',
      });
      expect(state.jammerNumber(1), '42');

      // CRG resets roles like this when the next jam starts.
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-a).Role': 'Bench',
      });

      expect(state.jammerNumber(1), isNull);
      state.startSeatAnonymously(state.team1Jammer);
      expect(state.team1Jammer.skaterNumber, '?');
      await engine.dispose();
    });

    test('is kept across jams when the scoreboard sends no reset', () async {
      // CRG leaves a jammer who is still in the penalty box as Jammer while
      // resetting the other team's.
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(boxed).RosterNumber': '42',
        'ScoreBoard.CurrentGame.Team(1).Skater(boxed).Role': 'Jammer',
        'ScoreBoard.CurrentGame.Team(2).Skater(free).RosterNumber': '7',
        'ScoreBoard.CurrentGame.Team(2).Skater(free).Role': 'Jammer',
        'ScoreBoard.CurrentGame.InJam': true,
      });
      await sendAndPump(channel, {'ScoreBoard.CurrentGame.InJam': false});
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.InJam': true,
        'ScoreBoard.CurrentGame.Team(2).Skater(free).Role': 'Bench',
      });

      expect(state.jammerNumber(1), '42');
      expect(state.jammerNumber(2), isNull);
      await engine.dispose();
    });

    test('the upcoming lineup jammer is shown before roles update', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-a).RosterNumber': '42',
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-b).RosterNumber': '77',
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-a).Role': 'Jammer',
      });
      // Between jams CRG moves the jammer position to the upcoming jam while
      // the just-ended jam's role stays in place.
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Position(Jammer).Skater': 'uuid-b',
      });

      expect(state.jammerNumber(1), '77');
      expect(state.displayNumber(state.team1Jammer), '77');
      expect(state.team1Jammer.isOccupied, isFalse);
      expect(state.team1Jammer.isRunning, isFalse);
      await engine.dispose();
    });

    test('an emptied lineup position falls back to the jammer role', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-a).RosterNumber': '42',
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-a).Role': 'Jammer',
        'ScoreBoard.CurrentGame.Team(1).Position(Jammer).Skater': 'uuid-a',
      });
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Position(Jammer).Skater': null,
      });

      expect(state.jammerNumber(1), '42');
      await engine.dispose();
    });

    test('resolves a role that arrives before the roster number', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(2).Skater(uuid-9).Role': 'Jammer',
      });
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(2).Skater(uuid-9).RosterNumber': '7',
      });

      state.startSeatAnonymously(state.team2Jammer);
      expect(state.team2Jammer.skaterNumber, '7');
      await engine.dispose();
    });

    test('a jammer role does not start a timer when the jam starts', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-123).RosterNumber': '42',
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-123).Role': 'Jammer',
        'ScoreBoard.CurrentGame.InJam': true,
      });

      expect(state.jamRunning, isTrue);
      expect(state.team1Jammer.isOccupied, isFalse);
      expect(state.team1Jammer.isRunning, isFalse);
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

  group('lineup tracking', () {
    const fielding = 'ScoreBoard.CurrentGame.Period(1).Jam(6).TeamJam(1)';

    test('marks skaters fielded in the current jam as on the track', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Clock(Period).Number': 1,
        'ScoreBoard.CurrentGame.Clock(Jam).Number': 6,
        '$fielding.Fielding(Jammer).SkaterNumber': '43',
        '$fielding.Fielding(Blocker2).SkaterNumber': '21',
        '$fielding.Fielding(Pivot).SkaterNumber': '?',
        'ScoreBoard.CurrentGame.Period(1).Jam(5).TeamJam(1).Fielding(Blocker1).SkaterNumber':
            '7',
        'ScoreBoard.CurrentGame.Period(1).Jam(6).TeamJam(2).Fielding(Jammer).SkaterNumber':
            '99',
      });

      expect(state.onTrackNumbers(1), {'43', '21'});
      expect(state.onTrackNumbers(2), {'99'});
      await engine.dispose();
    });

    test('accepts fieldings reported under the game id', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Clock(Period).Number': 1,
        'ScoreBoard.CurrentGame.Clock(Jam).Number': 7,
        'ScoreBoard.Game(473634e6).Period(1).Jam(7).TeamJam(1).Fielding(Jammer).SkaterNumber':
            '43',
      });

      expect(state.onTrackNumbers(1), {'43'});
      await engine.dispose();
    });

    test(
      'a skater moved out of a fielding is no longer on the track',
      () async {
        final (:engine, :channel, :state) = await setupEngine();
        await sendAndPump(channel, {
          'ScoreBoard.CurrentGame.Clock(Jam).Number': 6,
          '$fielding.Fielding(Blocker2).SkaterNumber': '21',
        });
        await sendAndPump(channel, {
          '$fielding.Fielding(Blocker2).SkaterNumber': '?',
        });

        expect(state.onTrackNumbers(1), isEmpty);
        await engine.dispose();
      },
    );

    test('includes the upcoming lineup between jams', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Clock(Jam).Number': 6,
        '$fielding.Fielding(Jammer).SkaterNumber': '43',
        'ScoreBoard.CurrentGame.Team(1).Position(Blocker1).RosterNumber': '21',
        'ScoreBoard.CurrentGame.Team(1).Position(Pivot).RosterNumber': '',
      });

      expect(state.onTrackNumbers(1), {'43', '21'});
      await engine.dispose();
    });

    test('is forgotten for a new game', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Game': 'game-one',
        'ScoreBoard.CurrentGame.Team(1).Position(Jammer).RosterNumber': '43',
      });
      await sendAndPump(channel, {'ScoreBoard.CurrentGame.Game': 'game-two'});

      expect(state.onTrackNumbers(1), isEmpty);
      await engine.dispose();
    });

    test('is not reported while disconnected', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Position(Jammer).RosterNumber': '43',
      });
      engine.disconnect();

      expect(state.onTrackNumbers(1), isEmpty);
      await engine.dispose();
    });

    test('registers the lineup paths', () async {
      final (:engine, :channel, state: _) = await setupEngine();
      final paths = channel.sentWithAction('Register').single['paths'] as List;

      expect(
        paths,
        containsAll([
          'ScoreBoard.CurrentGame.Period(*).Jam(*).TeamJam(*).Fielding(*).SkaterNumber',
          'ScoreBoard.CurrentGame.Team(*).Position(*).RosterNumber',
        ]),
      );
      await engine.dispose();
    });
  });

  group('reconnecting', () {
    test('failed retries leave the locally stopped jam alone', () {
      fakeAsync((fake) {
        final state = makeState();
        var attempts = 0;
        final engine = RemotePenaltyEngine(
          state,
          channelFactory: (_) {
            attempts++;
            throw Exception('CRG unreachable');
          },
          wakelockEnable: () {},
          wakelockDisable: () {},
        );
        engine.connect('http://localhost:8000');
        fake.flushMicrotasks();
        expect(engine.isLocal, isTrue);

        state.seatSkater(
          seat: state.team1Blocker1,
          number: '22',
          position: SkaterPosition.blocker,
        );
        engine.toggleJam(); // the real jam ended; the PBT stops it locally
        expect(state.jamRunning, isFalse);

        fake.elapse(const Duration(seconds: 10));
        expect(attempts, greaterThan(1));

        expect(state.jamRunning, isFalse);
        expect(state.jamNumber, 1);
        expect(state.team1Blocker1.isRunning, isFalse);
        expect(state.team1Blocker1.timeRemaining, const Duration(seconds: 30));
        engine.dispose();
      });
    });

    test('the old socket closing late does not drop a reconnect', () async {
      final channels = <FakeWebSocketChannel>[];
      final state = makeState();
      final engine = RemotePenaltyEngine(
        state,
        channelFactory: (_) {
          final channel = FakeWebSocketChannel();
          channels.add(channel);
          return channel;
        },
        wakelockEnable: () {},
        wakelockDisable: () {},
      );
      await engine.connect('http://localhost:8000');
      await engine.reconnect();
      expect(channels, hasLength(2));

      channels.first.dispose(); // old socket finishes closing
      await Future.microtask(() {});

      expect(engine.isLocal, isFalse);
      expect(state.connectionStatus, ConnectionStatus.connected);
      await engine.dispose();
    });
  });

  test('a jam ending while backgrounded stops timers when it ended', () {
    fakeAsync((fake) {
      final channel = FakeWebSocketChannel();
      final state = makeState();
      final alerts = FakeAlertScheduler();
      final engine = RemotePenaltyEngine(
        state,
        alerts: alerts,
        channelFactory: (_) => channel,
        wakelockEnable: () {},
        wakelockDisable: () {},
      );
      engine.connect('http://localhost:8000');
      fake.flushMicrotasks();
      channel.send({'ScoreBoard.CurrentGame.InJam': true});
      fake.flushMicrotasks();
      state.seatSkater(
        seat: state.team1Blocker1,
        number: '22',
        position: SkaterPosition.blocker,
      );

      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.paused,
      );
      fake.flushMicrotasks();
      expect(alerts.scheduled, hasLength(2));
      expect(alerts.scheduled!.last.body, contains('if the jam is still'));

      // The socket stays up in the background and CRG ends the jam.
      fake.elapse(const Duration(seconds: 4));
      channel.send({'ScoreBoard.CurrentGame.InJam': false});
      fake.flushMicrotasks();
      expect(state.team1Blocker1.timeRemaining, const Duration(seconds: 26));
      expect(alerts.scheduled, isEmpty);

      fake.elapse(const Duration(seconds: 20));
      WidgetsBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      expect(state.team1Blocker1.timeRemaining, const Duration(seconds: 26));
      engine.dispose();
      channel.dispose();
    });
  });
}

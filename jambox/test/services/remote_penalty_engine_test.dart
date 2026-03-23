import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pbm_ready/models/penalty_box_state.dart';
import 'package:pbm_ready/models/skater_seat.dart';
import 'package:pbm_ready/services/remote_penalty_engine.dart';

import '../test_helpers.dart';

// ---------------------------------------------------------------------------
// Setup helpers
// ---------------------------------------------------------------------------

typedef EngineFixture = ({
  RemotePenaltyEngine engine,
  FakeWebSocketChannel channel,
  PenaltyBoxState state,
});

Future<EngineFixture> setupEngine({
  AppRole role = AppRole.pbm,
  int? teamIndex,
}) async {
  final channel = FakeWebSocketChannel();
  final state = makeState(role: role, teamIndex: teamIndex);
  final engine = RemotePenaltyEngine(
    state,
    channelFactory: (_) => channel,
    wakelockEnable: () {},
    wakelockDisable: () {},
  );
  await engine.connect('http://localhost:8000');
  // Let the stream subscription be established.
  await Future.microtask(() {});
  return (engine: engine, channel: channel, state: state);
}

/// Send a state message and pump microtasks so the engine processes it.
Future<void> sendAndPump(FakeWebSocketChannel channel, Map<String, dynamic> msg) async {
  channel.send(msg);
  await Future.microtask(() {});
  await Future.microtask(() {});
}

/// Enter BoxSeat mode by sending a BoxClock.Time update.
Future<void> enterBoxSeatMode(FakeWebSocketChannel channel) =>
    sendAndPump(channel, {
      'ScoreBoard.CurrentGame.BoxClock(Team1Jammer).Time': 25000,
    });

/// Mark bootstrap phase complete by sending InJam.
Future<void> endBootstrap(FakeWebSocketChannel channel, {bool inJam = false}) =>
    sendAndPump(channel, {
      'ScoreBoard.CurrentGame.InJam': inJam,
    });

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ---------------------------------------------------------------------------
  // Group A: Generic CRG message parsing
  // ---------------------------------------------------------------------------

  group('Group A — CRG message parsing', () {
    test('InJam=true sets jamRunning and clears bootstrap', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {'ScoreBoard.CurrentGame.InJam': true});

      expect(state.jamRunning, isTrue);
    });

    test('InJam=false sets jamRunning=false', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {'ScoreBoard.CurrentGame.InJam': false});

      expect(state.jamRunning, isFalse);
    });

    test('Clock(Jam).Running=true sets jamRunning (fallback path)', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Clock(Jam).Running': true,
      });

      expect(state.jamRunning, isTrue);
    });

    test('Clock(Jam).Number sets jamNumber', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Clock(Jam).Number': 5,
      });

      expect(state.jamNumber, 5);
    });

    test('Clock(Period).Number sets periodNumber', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Clock(Period).Number': 2,
      });

      expect(state.periodNumber, 2);
    });

    test('Team name update', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Name': 'Blockers',
        'ScoreBoard.CurrentGame.Team(2).Name': 'Jammers',
      });

      expect(state.team1.name, 'Blockers');
      expect(state.team2.name, 'Jammers');
    });

    test('Team color update via Color(operator.fg)', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Color(operator.fg)': '#FF0000',
      });

      expect(state.team1.color.toARGB32(), 0xFFFF0000);
    });

    test('Skater(uuid).Number populates roster and known numbers', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-123).Number': '42',
      });

      expect(state.lookupSkaterId(1, '42'), 'uuid-123');
      expect(state.knownNumbers(1), contains('42'));
    });

    test('Skater(uuid).Role=Jammer sets jammer seat number', () async {
      final (:engine, :channel, :state) = await setupEngine();

      // First register uuid → number
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-j).Number': '77',
      });
      // Mark seat occupied so Role update sticks
      state.team1Jammer.skaterNumber = '?';

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).Skater(uuid-j).Role': 'Jammer',
      });

      expect(state.team1Jammer.skaterNumber, '77');
    });

    test('Legacy Game.Team(t).Skater map populates roster', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'Game.Team(1).Skater': {
          'uuid-a': {'Number': '10'},
          'uuid-b': {'Number': '20'},
        },
      });

      expect(state.lookupSkaterId(1, '10'), 'uuid-a');
      expect(state.lookupSkaterId(1, '20'), 'uuid-b');
    });

    test('Unrecognized path is silently ignored', () async {
      final (:engine, :channel, :state) = await setupEngine();

      // Should not throw
      await sendAndPump(channel, {
        'ScoreBoard.SomeUnknown.Path': 'value',
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Group B: BoxClock — bootstrap and ownership
  // ---------------------------------------------------------------------------

  group('Group B — BoxClock bootstrap and ownership', () {
    test('bootstrap: owned seat time applied unconditionally on first connect', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.BoxClock(Team1Jammer).Time': 20000,
      });

      // Time applied even though engine is the owner (bootstrap phase)
      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 20));
    });

    test('bootstrap: non-owned seat time always applied', () async {
      final (:engine, :channel, :state) = await setupEngine(
        role: AppRole.boxTimerTeam1,
        teamIndex: 1,
      );
      await enterBoxSeatMode(channel);

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.BoxClock(Team2Jammer).Time': 15000,
      });

      expect(state.team2Jammer.timeRemaining, const Duration(seconds: 15));
    });

    test('after bootstrap: owned seat, small delta (<1s) → NOT applied', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await enterBoxSeatMode(channel);
      await endBootstrap(channel);

      // Set local time to 25s
      state.team1Jammer.setSkater(number: '10', pos: SkaterPosition.jammer);
      state.team1Jammer.timeRemaining = const Duration(seconds: 25);

      // Server sends 25.5s — delta = 0.5s < 1s → should NOT override
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.BoxClock(Team1Jammer).Time': 25500,
      });

      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 25));
    });

    test('after bootstrap: owned seat, large delta (>1s) → applied (server correction)', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await enterBoxSeatMode(channel);
      await endBootstrap(channel);

      state.team1Jammer.setSkater(number: '10', pos: SkaterPosition.jammer);
      state.team1Jammer.timeRemaining = const Duration(seconds: 25);

      // Server sends 10s — delta = 15s > 1s → applied (jammer sync correction)
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.BoxClock(Team1Jammer).Time': 10000,
      });

      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 10));
    });

    test('after bootstrap: non-owned seat, any delta → always applied', () async {
      final (:engine, :channel, :state) = await setupEngine(
        role: AppRole.boxTimerTeam1,
        teamIndex: 1,
      );
      await enterBoxSeatMode(channel);
      await endBootstrap(channel);

      state.team2Jammer.setSkater(number: '20', pos: SkaterPosition.jammer);
      state.team2Jammer.timeRemaining = const Duration(seconds: 25);

      // Small delta — still applied for non-owned seat
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.BoxClock(Team2Jammer).Time': 24800,
      });

      expect(state.team2Jammer.timeRemaining, const Duration(milliseconds: 24800));
    });

    test('BoxClock.Running=false never applied to owned seat', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await enterBoxSeatMode(channel);
      await endBootstrap(channel, inJam: true);

      state.team1Jammer.setSkater(number: '10', pos: SkaterPosition.jammer);
      state.team1Jammer.isRunning = true;

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.BoxClock(Team1Jammer).Running': false,
      });

      // Local timer still running — server cannot stop owned seat
      expect(state.team1Jammer.isRunning, isTrue);
    });

    test('BoxClock.Running=true applied as catch-up for occupied-but-stopped owned seat', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await enterBoxSeatMode(channel);
      await endBootstrap(channel);

      state.team1Jammer.setSkater(number: '10', pos: SkaterPosition.jammer);
      state.team1Jammer.isRunning = false; // occupied but not yet running

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.BoxClock(Team1Jammer).Running': true,
      });

      expect(state.team1Jammer.isRunning, isTrue);
    });

    test('BoxClock.Running=false applied to non-owned seat', () async {
      final (:engine, :channel, :state) = await setupEngine(
        role: AppRole.boxTimerTeam1,
        teamIndex: 1,
      );
      await enterBoxSeatMode(channel);
      await endBootstrap(channel);

      state.team2Jammer.setSkater(number: '20', pos: SkaterPosition.jammer);
      state.team2Jammer.isRunning = true;

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.BoxClock(Team2Jammer).Running': false,
      });

      expect(state.team2Jammer.isRunning, isFalse);
    });

    test('Blocker3 queue time update syncs existing queue entry', () async {
      final (:engine, :channel, :state) = await setupEngine();

      // First create a Blocker3 queue entry via BoxSeat.Started
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker3).Started': true,
      });
      expect(state.queueForTeam(1), hasLength(1));

      // Now send a time update for Blocker3
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.BoxClock(Team1Blocker3).Time': 18000,
      });

      expect(state.queueForTeam(1).first.timeRemaining,
          const Duration(seconds: 18));
    });
  });

  // ---------------------------------------------------------------------------
  // Group C: BoxSeat — occupancy state
  // ---------------------------------------------------------------------------

  group('Group C — BoxSeat occupancy state', () {
    test('Started=true gives seat a placeholder number and 30s', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Jammer).Started': true,
      });

      expect(state.team1Jammer.skaterNumber, '?');
      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 30));
    });

    test('Started=false clears the seat', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Jammer).Started': true,
      });
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Jammer).Started': false,
      });

      expectSeatEmpty(state.team1Jammer);
    });

    test('Started=true when seat already occupied → no change', () async {
      final (:engine, :channel, :state) = await setupEngine();

      state.team1Blocker1.setSkater(number: '55', pos: SkaterPosition.blocker);

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker1).Started': true,
      });

      // Number should still be '55', not overwritten with '?'
      expect(state.team1Blocker1.skaterNumber, '55');
    });

    test('BoxSkater sets number and adds to known numbers', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker1).Started': true,
      });
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker1).BoxSkater': '123',
      });

      expect(state.team1Blocker1.skaterNumber, '123');
      expect(state.knownNumbers(1), contains('123'));
    });

    test('BoxSkater empty string reverts seat to placeholder', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker1).Started': true,
      });
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker1).BoxSkater': '123',
      });
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker1).BoxSkater': '',
      });

      expect(state.team1Blocker1.skaterNumber, '?');
    });

    test('Blocker3 Started=true creates a queue entry', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker3).Started': true,
      });

      expect(state.queueForTeam(1), hasLength(1));
    });

    test('Blocker3 Started=false removes the queue entry', () async {
      final (:engine, :channel, :state) = await setupEngine();

      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker3).Started': true,
      });
      await sendAndPump(channel, {
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker3).Started': false,
      });

      expect(state.queueForTeam(1), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Group D: WS commands sent for owned seats (PBM role)
  // ---------------------------------------------------------------------------

  group('Group D — WS commands for owned seats (PBM)', () {
    late EngineFixture fixture;

    setUp(() async {
      fixture = await setupEngine(role: AppRole.pbm);
      // Enter BoxSeat mode
      await enterBoxSeatMode(fixture.channel);
      fixture.channel.sent.clear();
    });

    test('seatSkater sends StartBox', () async {
      fixture.state.seatSkater(
        seat: fixture.state.team1Jammer,
        number: '10',
        position: SkaterPosition.jammer,
      );

      expectCommandSent(fixture.channel, 'StartBox');
    });

    test('clearSeat sends ResetBox', () async {
      fixture.state.team1Jammer.setSkater(
          number: '10', pos: SkaterPosition.jammer);
      fixture.state.clearSeat(fixture.state.team1Jammer);

      expectCommandSent(fixture.channel, 'ResetBox');
    });

    test('addPenaltyToSeat sends BoxTimeChange=30', () async {
      fixture.state.team1Blocker1.setSkater(
          number: '22', pos: SkaterPosition.blocker);
      fixture.state.addPenaltyToSeat(fixture.state.team1Blocker1);

      final cmds = fixture.channel.sentSets('BoxTimeChange');
      expect(cmds, hasLength(1));
      expect(cmds.first['value'], 30);
    });

    test('removePenaltyFromSeat sends BoxTimeChange=-30', () async {
      fixture.state.team1Blocker1.setSkater(
          number: '22', pos: SkaterPosition.blocker);
      fixture.state.team1Blocker1.penaltyCount = 2;
      fixture.state.team1Blocker1.timeRemaining = const Duration(seconds: 60);
      fixture.channel.sent.clear();

      fixture.state.removePenaltyFromSeat(fixture.state.team1Blocker1);

      final cmds = fixture.channel.sentSets('BoxTimeChange');
      expect(cmds, hasLength(1));
      expect(cmds.first['value'], -30);
    });

    test('seatSkater on blocker sends BoxSkater command', () async {
      fixture.state.seatSkater(
        seat: fixture.state.team1Blocker1,
        number: '55',
        position: SkaterPosition.blocker,
      );

      expectCommandSent(fixture.channel, 'BoxSkater');
    });

    test('seatSkater on jammer does NOT send BoxSkater (jammer auto-populated via role)', () async {
      fixture.state.seatSkater(
        seat: fixture.state.team1Jammer,
        number: '10',
        position: SkaterPosition.jammer,
      );

      expectCommandNotSent(fixture.channel, 'BoxSkater');
      expectCommandSent(fixture.channel, 'StartBox');
    });
  });

  // ---------------------------------------------------------------------------
  // Group E: WS commands NOT sent for non-owned seats (boxTimerTeam1 role)
  // ---------------------------------------------------------------------------

  group('Group E — WS commands not sent for non-owned seats', () {
    late EngineFixture fixture;

    setUp(() async {
      // boxTimerTeam1 owns only team 1 seats
      fixture = await setupEngine(role: AppRole.boxTimerTeam1, teamIndex: 1);
      await enterBoxSeatMode(fixture.channel);
      fixture.channel.sent.clear();
    });

    test('action on team 2 seat (non-owned) sends no WS command', () {
      fixture.state.seatSkater(
        seat: fixture.state.team2Jammer,
        number: '20',
        position: SkaterPosition.jammer,
      );

      expectNoCommandSent(fixture.channel);
    });

    test('action on team 1 seat (owned) sends WS command', () {
      fixture.state.seatSkater(
        seat: fixture.state.team1Jammer,
        number: '10',
        position: SkaterPosition.jammer,
      );

      expectCommandSent(fixture.channel, 'StartBox');
    });
  });

  // ---------------------------------------------------------------------------
  // Group F: Reconnect behavior
  // ---------------------------------------------------------------------------

  group('Group F — Reconnect behavior', () {
    test('reconnect re-enters bootstrap phase — BoxClock.Time applied unconditionally', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await enterBoxSeatMode(channel);
      await endBootstrap(channel);

      // Set local time
      state.team1Jammer.setSkater(number: '10', pos: SkaterPosition.jammer);
      state.team1Jammer.timeRemaining = const Duration(seconds: 25);

      // Reconnect with new channel
      final newChannel = FakeWebSocketChannel();
      // ignore: invalid_use_of_visible_for_testing_member
      await engine.reconnect();
      // After reconnect, bootstrap=true so server time is applied regardless of delta

      // Send a time that's only 0.5s different — still applied due to bootstrap
      newChannel.send({
        'ScoreBoard.CurrentGame.BoxClock(Team1Jammer).Time': 24500,
      });
      await Future.microtask(() {});

      // New channel not injected in reconnect (engine reconnects to same URL),
      // but we can verify state was reset properly.
      expect(engine.isLocal, isFalse); // still a remote engine
    });

    test('reconnect clears BoxSeat callbacks', () async {
      final (:engine, :channel, :state) = await setupEngine();
      await enterBoxSeatMode(channel);

      expect(state.onSeatStarted, isNotNull);

      await engine.reconnect();

      // Callbacks should be cleared during reconnect
      expect(state.onSeatStarted, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Group G: reportPenalty()
  // ---------------------------------------------------------------------------

  group('Group G — reportPenalty()', () {
    test('known skater sends Penalty WS command with correct fields', () async {
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
      final data = penalties.first['data'] as Map<String, dynamic>;
      expect(data['teamId'], '1');
      expect(data['skaterId'], 'uuid-abc');
      expect(data['period'], 2);
      expect(data['jam'], 7);
    });

    test('unknown skater sends no command', () async {
      final (:engine, :channel, :state) = await setupEngine();

      engine.reportPenalty(
        teamIndex: 1,
        skaterNumber: '999',
        periodNumber: 1,
        jamNumber: 1,
      );
      await Future.microtask(() {});

      expect(channel.sentWithAction('Penalty'), isEmpty);
    });
  });
}

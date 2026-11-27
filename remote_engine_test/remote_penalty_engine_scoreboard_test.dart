// Exercises RemotePenaltyEngine directly against a real CRG Scoreboard over
// WebSocket. This covers the mainline compatibility path where CRG supplies
// game state while JamBox maintains penalty-seat timers locally; it deliberately
// has no widget tree or emulator in the test loop.
import 'package:flutter/services.dart';
import 'package:allure_flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jam_ready/models/penalty_box_state.dart';
import 'package:jam_ready/models/skater_seat.dart';
import 'package:jam_ready/services/remote_penalty_engine.dart';

import 'utilities/remote_engine_test_helpers.dart';
import 'utilities/scoreboard_operator_client.dart';

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

  final host = scoreboardHost();
  final port = scoreboardPort();
  const jammerSkaterId = '11111111-2222-3333-4444-555555555555';
  const replacementJammerSkaterId = '66666666-7777-8888-9999-000000000000';

  late PenaltyBoxState state;
  late RemotePenaltyEngine engine;
  late ScoreboardOperatorClient operatorClient;

  setUp(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    state = PenaltyBoxState();
    engine = RemotePenaltyEngine(state);
    await engine.connect('ws://$host:$port');
    await waitUntil(
      () => state.connectionStatus == ConnectionStatus.connected,
      label: 'penalty engine connects to scoreboard server',
    );
    operatorClient = await ScoreboardOperatorClient.connect(
      operatorWsUri(host, port),
    );
  });

  tearDown(() async {
    await engine.dispose();
    await operatorClient.close();
  });

  test(
    'remote jam state controls locally tracked penalty-seat timers',
    () async {
      log('action: startNewGame');
      await operatorClient.startNewGame();
      await waitUntil(
        () => !state.jamRunning,
        label: 'remote game is between jams',
      );

      final blocker = state.team1Blocker1;
      state.seatSkater(
        seat: blocker,
        number: '42',
        position: SkaterPosition.blocker,
      );
      expect(blocker.isOccupied, isTrue);
      expect(blocker.isRunning, isFalse);

      log('action: stopJam (start lineup)');
      await clockAction(operatorClient.stopJam);
      log('action: startJam');
      await clockAction(operatorClient.startJam);
      await waitUntil(
        () => state.jamRunning && blocker.isRunning,
        label: 'remote jam start starts the occupied penalty seat timer',
      );

      log('action: stopJam (end jam)');
      await clockAction(operatorClient.stopJam);
      await waitUntil(
        () => !state.jamRunning && !blocker.isRunning,
        label: 'remote jam end pauses the occupied penalty seat timer',
      );
    },
  );

  test('the jam clock running out leaves the penalty timers running', () async {
    log('action: startNewGame');
    await operatorClient.startNewGame();
    await waitUntil(
      () => !state.jamRunning,
      label: 'remote game is between jams',
    );

    final blocker = state.team1Blocker1;
    state.seatSkater(
      seat: blocker,
      number: '42',
      position: SkaterPosition.blocker,
    );

    log('action: stopJam (start lineup)');
    await clockAction(operatorClient.stopJam);
    log('action: startJam');
    await clockAction(operatorClient.startJam);
    await waitUntil(
      () => state.jamRunning && blocker.isRunning,
      label: 'remote jam start starts the occupied penalty seat timer',
    );

    // Without auto-end, CRG stops the jam clock at 2:00 but the jam goes on
    // until it is called.
    log('action: run the jam clock out');
    operatorClient.setValue('ScoreBoard.CurrentGame.Clock(Jam).Time', '500');
    await Future.delayed(const Duration(seconds: 2));
    expect(state.jamRunning, isTrue, reason: 'the jam has not been called');
    expect(blocker.isRunning, isTrue);

    log('action: stopJam (end jam)');
    await clockAction(operatorClient.stopJam);
    await waitUntil(
      () => !state.jamRunning && !blocker.isRunning,
      label: 'calling the jam pauses the occupied penalty seat timer',
    );
  });

  test(
    'setting the jammer on the scoreboard does not start a penalty timer',
    () async {
      log('action: startNewGame');
      await operatorClient.startNewGame();
      await waitUntil(
        () => !state.jamRunning,
        label: 'remote game is between jams',
      );

      log('action: add skater #17 to team 1 and set as jammer');
      operatorClient.addSkater(1, jammerSkaterId, '17');
      await waitUntil(
        () => state.lookupSkaterId(1, '17') == jammerSkaterId,
        label: 'roster skater #17 reaches the penalty engine',
      );
      operatorClient.setJammer(1, jammerSkaterId);
      // Nothing observable changes when the role is ignored correctly, so give
      // the Role update time to arrive before asserting on its absence.
      await Future.delayed(const Duration(seconds: 1));

      final jammer = state.team1Jammer;
      expect(jammer.isOccupied, isFalse, reason: 'no penalty was reported');
      expect(jammer.state, SeatState.empty);

      log('action: stopJam (start lineup)');
      await clockAction(operatorClient.stopJam);
      log('action: startJam');
      await clockAction(operatorClient.startJam);
      await waitUntil(
        () => state.jamRunning,
        label: 'remote jam start reaches the penalty engine',
      );
      await Future.delayed(const Duration(seconds: 1));

      expect(jammer.isOccupied, isFalse);
      expect(jammer.isRunning, isFalse);
      expect(jammer.timeRemaining, Duration.zero);

      // Starting the jammer's timer is what seats them, using the number the
      // scoreboard reported.
      state.startSeatAnonymously(jammer);
      expect(jammer.skaterNumber, '17');
      expect(jammer.isRunning, isTrue);
    },
  );

  test(
    'changing the scoreboard jammer does not affect a running jammer seat',
    () async {
      log('action: startNewGame');
      await operatorClient.startNewGame();
      await waitUntil(
        () => !state.jamRunning,
        label: 'remote game is between jams',
      );

      operatorClient.addSkater(1, jammerSkaterId, '17');
      operatorClient.addSkater(1, replacementJammerSkaterId, '23');
      await waitUntil(
        () =>
            state.lookupSkaterId(1, '17') != null &&
            state.lookupSkaterId(1, '23') != null,
        label: 'roster skaters reach the penalty engine',
      );
      operatorClient.setJammer(1, jammerSkaterId);
      await waitUntil(
        () => state.jammerNumber(1) == '17',
        label: 'scoreboard jammer #17 reaches the penalty engine',
      );

      log('action: stopJam (start lineup)');
      await clockAction(operatorClient.stopJam);
      log('action: startJam');
      await clockAction(operatorClient.startJam);
      await waitUntil(() => state.jamRunning, label: 'remote jam starts');

      final jammer = state.team1Jammer;
      state.startSeatAnonymously(jammer);
      expect(jammer.skaterNumber, '17');
      expect(jammer.isRunning, isTrue);

      log('action: replace jammer with #23');
      operatorClient.setJammer(1, replacementJammerSkaterId);
      await waitUntil(
        () => state.jammerNumber(1) == '23',
        label: 'replacement jammer #23 reaches the penalty engine',
      );

      expect(jammer.skaterNumber, '17');
      expect(jammer.isRunning, isTrue);
      expect(jammer.penaltyCount, 1);
      expect(jammer.unmatchedPenalties, 1);
      expect(jammer.position, SkaterPosition.jammer);
    },
  );

  // Entering a lineup is bookkeeping for the scoreboard: it must never start,
  // pause or release a penalty timer. The only effect on the box is that an
  // open jammer card shows the lineup's jammer number.
  test('setting a lineup leaves penalty timers alone and fills open jammer '
      'card numbers', () async {
    // Skater IDs are unique per game, unlike the IDs reused by other tests.
    String id(int n) =>
        'eeeeeeee-1111-2222-3333-${n.toString().padLeft(12, '0')}';
    final team1Lineup = {
      'Jammer': (id(1), '17'),
      'Pivot': (id(2), '3'),
      'Blocker1': (id(3), '4'),
      'Blocker2': (id(4), '5'),
      'Blocker3': (id(5), '6'),
    };
    final team2Lineup = {
      'Jammer': (id(11), '98'),
      'Pivot': (id(12), '30'),
      'Blocker1': (id(13), '40'),
    };
    final team2BoxedJammer = (id(10), '99');

    log('action: startNewGame');
    await operatorClient.startNewGame();
    await waitUntil(
      () => !state.jamRunning,
      label: 'remote game is between jams',
    );

    for (final (uuid, number) in team1Lineup.values) {
      operatorClient.addSkater(1, uuid, number);
    }
    for (final (uuid, number) in [...team2Lineup.values, team2BoxedJammer]) {
      operatorClient.addSkater(2, uuid, number);
    }
    await waitUntil(
      () =>
          team1Lineup.values.every(
            (s) => state.lookupSkaterId(1, s.$2) != null,
          ) &&
          team2Lineup.values.every(
            (s) => state.lookupSkaterId(2, s.$2) != null,
          ) &&
          state.lookupSkaterId(2, team2BoxedJammer.$2) != null,
      label: 'roster skaters reach the penalty engine',
    );
    operatorClient.setJammer(2, team2BoxedJammer.$1);
    await waitUntil(
      () => state.jammerNumber(2) == '99',
      label: 'team 2 jammer #99 reaches the penalty engine',
    );

    log('jam 1: put skaters in the box in every timer state');
    await clockAction(operatorClient.stopJam);
    await clockAction(operatorClient.startJam);
    await waitUntil(() => state.jamRunning, label: 'jam 1 starts');

    final running = state.team1Blocker1;
    final paused = state.team1Blocker2;
    final released = state.team2Blocker1;
    final boxedJammer = state.team2Jammer;
    state.seatSkater(
      seat: running,
      number: '42',
      position: SkaterPosition.blocker,
    );
    state.seatSkater(
      seat: paused,
      number: '43',
      position: SkaterPosition.blocker,
    );
    state.toggleSeatTimer(paused);
    state.seatSkater(
      seat: released,
      number: '44',
      position: SkaterPosition.blocker,
    );
    state.adjustTime(released, const Duration(seconds: -30));
    state.startSeatAnonymously(boxedJammer);
    expect(boxedJammer.skaterNumber, '99');
    expect(released.state, SeatState.done);
    operatorClient.setJammerInPenaltyBox(2, true);

    await clockAction(operatorClient.stopJam);
    await waitUntil(
      () => !state.jamRunning && state.seats.every((s) => !s.isRunning),
      label: 'jam 1 ends and pauses every seat',
    );

    snapshot(SkaterSeat s) => (
      number: s.skaterNumber,
      preset: s.presetNumber,
      running: s.isRunning,
      remaining: s.timeRemaining,
      overtime: s.overtime,
      penalties: s.penaltyCount,
      unmatched: s.unmatchedPenalties,
      state: s.state,
    );
    final before = state.seats.map(snapshot).toList();

    log('action: set both lineups for jam 2');
    team1Lineup.forEach((pos, s) => operatorClient.setPosition(1, pos, s.$1));
    team2Lineup.forEach((pos, s) => operatorClient.setPosition(2, pos, s.$1));
    await waitUntil(
      () => state.jammerNumber(1) == '17' && state.jammerNumber(2) == '98',
      label: 'both lineup jammers reach the penalty engine',
    );
    // Blocker roles have no observable effect; give them time to arrive.
    await Future.delayed(const Duration(seconds: 1));

    expect(
      state.seats.map(snapshot).toList(),
      before,
      reason: 'a lineup never starts, pauses, or ends a penalty timer',
    );
    expect(state.team1Jammer.state, SeatState.empty);
    expect(
      state.displayNumber(state.team1Jammer),
      '17',
      reason: 'open jammer card shows the lineup jammer',
    );
    expect(
      state.displayNumber(boxedJammer),
      '99',
      reason: 'a seated jammer keeps their own number',
    );
    for (final seat in [
      state.team1Blocker1,
      state.team1Blocker2,
      state.team1Blocker3,
      state.team2Blocker1,
      state.team2Blocker2,
      state.team2Blocker3,
    ].where((s) => s.isEmpty)) {
      expect(state.displayNumber(seat), isNull, reason: 'blockers not filled');
    }

    log('action: startJam (jam 2)');
    await clockAction(operatorClient.startJam);
    await waitUntil(
      () => state.jamRunning && running.isRunning,
      label: 'jam 2 starts and resumes serving seats',
    );
    expect(state.team1Jammer.isEmpty, isTrue, reason: 'jammer not boxed');
    expect(state.team1Jammer.isRunning, isFalse);
    expect(boxedJammer.isRunning, isTrue);
    expect(released.state, SeatState.done);
  });

  // CRG resets a team's jammer role when the next jam starts, except that a
  // jammer still in the penalty box carries over into that jam.
  test('scoreboard jammer is forgotten when the next jam starts, unless the '
      'jammer is in the penalty box', () async {
    // Skater IDs are unique per game, unlike the IDs reused by other tests.
    const team1JammerId = 'bbbbbbbb-1111-2222-3333-444444444444';
    const team2JammerId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

    log('action: startNewGame');
    await operatorClient.startNewGame();
    await waitUntil(
      () => !state.jamRunning,
      label: 'remote game is between jams',
    );

    operatorClient.addSkater(1, team1JammerId, '17');
    operatorClient.addSkater(2, team2JammerId, '99');
    await waitUntil(
      () =>
          state.lookupSkaterId(1, '17') != null &&
          state.lookupSkaterId(2, '99') != null,
      label: 'roster skaters reach the penalty engine',
    );

    Future<void> setBothJammers() async {
      operatorClient.setJammer(1, team1JammerId);
      operatorClient.setJammer(2, team2JammerId);
      await waitUntil(
        () => state.jammerNumber(1) == '17' && state.jammerNumber(2) == '99',
        label: 'both scoreboard jammers reach the penalty engine',
      );
    }

    log('jam 1: lineup, then jam, nobody boxed');
    await setBothJammers();
    await clockAction(operatorClient.stopJam);
    await clockAction(operatorClient.startJam);
    await waitUntil(() => state.jamRunning, label: 'jam 1 starts');
    await clockAction(operatorClient.stopJam);
    await waitUntil(() => !state.jamRunning, label: 'jam 1 ends');

    log('action: startJam (jam 2)');
    await clockAction(operatorClient.startJam);
    await waitUntil(
      () => state.jammerNumber(1) == null && state.jammerNumber(2) == null,
      label: 'both jammers are forgotten when the next jam starts',
    );

    log('jam 2: team 1 jammer ends the jam in the penalty box');
    await setBothJammers();
    operatorClient.setJammerInPenaltyBox(1, true);
    await clockAction(operatorClient.stopJam);
    await waitUntil(() => !state.jamRunning, label: 'jam 2 ends');

    log('action: startJam (jam 3)');
    await clockAction(operatorClient.startJam);
    await waitUntil(
      () => state.jammerNumber(2) == null,
      label: 'unboxed team 2 jammer is forgotten when the next jam starts',
    );
    expect(state.jammerNumber(1), '17', reason: 'boxed jammer carries over');

    // The carried-over jammer is still what auto-fills a jammer timer.
    state.startSeatAnonymously(state.team1Jammer);
    expect(state.team1Jammer.skaterNumber, '17');
  });

  // WFTDA §4.4 jammer swap while CRG drives the jam. The test ticks seat time
  // explicitly for the swap itself; real time also passes during each CRG
  // round trip, so later checks use bounds instead of exact times.
  test('jammer swap during a remote jam shows sat time, then flags both '
      'jammers sitting when the first returns', () async {
    // Skater IDs are unique per game, unlike the IDs reused by other tests.
    const team1JammerId = 'cccccccc-1111-2222-3333-444444444444';
    const team2JammerId = 'dddddddd-1111-2222-3333-444444444444';

    log('action: startNewGame');
    await operatorClient.startNewGame();
    await waitUntil(
      () => !state.jamRunning,
      label: 'remote game is between jams',
    );

    operatorClient.addSkater(1, team1JammerId, '17');
    operatorClient.addSkater(2, team2JammerId, '99');
    await waitUntil(
      () =>
          state.lookupSkaterId(1, '17') != null &&
          state.lookupSkaterId(2, '99') != null,
      label: 'roster skaters reach the penalty engine',
    );
    operatorClient.setJammer(1, team1JammerId);
    operatorClient.setJammer(2, team2JammerId);
    await waitUntil(
      () => state.jammerNumber(1) == '17' && state.jammerNumber(2) == '99',
      label: 'both scoreboard jammers reach the penalty engine',
    );

    log('action: stopJam (start lineup)');
    await clockAction(operatorClient.stopJam);
    log('action: startJam');
    await clockAction(operatorClient.startJam);
    await waitUntil(() => state.jamRunning, label: 'remote jam starts');

    final team1 = state.team1Jammer;
    final team2 = state.team2Jammer;

    log('team 1 jammer sits 12 seconds, then team 2 jammer arrives');
    state.startSeatAnonymously(team1);
    state.tick(const Duration(seconds: 12));
    state.startSeatAnonymously(team2);

    expect(team1.skaterNumber, '17');
    expect(team2.skaterNumber, '99');
    expect(team1.timeRemaining, Duration.zero, reason: 'swap releases #17');
    expect(team2.timeRemaining, const Duration(seconds: 12));
    expect(state.swapSatTime(1), const Duration(seconds: 12));
    expect(state.swapSatTime(2), isNull);
    expect(state.bothJammersSitting, isFalse);

    log('team 1 jammer released; the sat note stays');
    state.clearSeat(team1);
    expect(state.swapSatTime(1), const Duration(seconds: 12));

    log('action: stopJam (end jam) with team 2 jammer still serving');
    await clockAction(operatorClient.stopJam);
    await waitUntil(
      () => !state.jamRunning && !team2.isRunning,
      label: 'remote jam end pauses the swapped jammer timer',
    );
    final owedAtJamEnd = team2.timeRemaining;
    expect(owedAtJamEnd, greaterThan(Duration.zero));
    expect(owedAtJamEnd, lessThanOrEqualTo(const Duration(seconds: 12)));
    expect(state.swapSatTime(1), const Duration(seconds: 12));

    log('action: startJam (jam 2)');
    await clockAction(operatorClient.startJam);
    await waitUntil(
      () => state.jamRunning && team2.isRunning,
      label: 'next remote jam resumes the swapped jammer timer',
    );

    log('team 1 jammer returns while team 2 jammer is still serving');
    operatorClient.setJammer(1, team1JammerId);
    await waitUntil(
      () => state.jammerNumber(1) == '17',
      label: 'scoreboard jammer #17 reaches the penalty engine',
    );
    state.startSeatAnonymously(team1);
    expect(team1.timeRemaining, const Duration(seconds: 30));
    expect(team2.timeRemaining, greaterThan(Duration.zero));
    expect(team2.timeRemaining, lessThanOrEqualTo(owedAtJamEnd));
    expect(state.swapSatTime(1), isNull, reason: 'new trip replaces note');
    expect(state.bothJammersSitting, isTrue);
    expect(state.bothSittingReason(1), JammerBoxReason.newPenalty);
    expect(state.bothSittingReason(2), JammerBoxReason.swapTime);
    expect(state.firstJammerOut, same(team2));

    log('team 2 jammer finishes and is released');
    state.tick(team2.timeRemaining);
    expect(team2.timeRemaining, Duration.zero);
    expect(state.bothJammersSitting, isFalse);
    state.clearSeat(team2);
    expect(team1.isOccupied, isTrue);
    expect(team1.timeRemaining, greaterThan(Duration.zero));
  });
}

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
}

// Exercises RemotePenaltyEngine directly against a real CRG Scoreboard over
// WebSocket. This covers the mainline compatibility path where CRG supplies
// game state while JamBox maintains penalty-seat timers locally; it deliberately
// has no widget tree or emulator in the test loop.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
    'feature-pbt server BoxSeat state is tracked remotely',
    () async {
      log('action: startNewGame');
      await operatorClient.startNewGame();

      await waitUntil(
        () => state.onSeatStarted != null,
        label: 'feature-pbt BoxSeat protocol is discovered',
      );

      log('operator action: start team 1 blocker box seat');
      operatorClient.setValue(
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker1).StartBox',
        true,
      );
      await waitUntil(
        () => state.team1Blocker1.isOccupied,
        label: 'server BoxSeat Started update occupies blocker seat',
      );
      expect(state.team1Blocker1.skaterNumber, '?');
      expect(state.team1Blocker1.timeRemaining, const Duration(seconds: 30));

      log('operator action: add 30 seconds to blocker box time');
      operatorClient.setValue(
        'ScoreBoard.CurrentGame.Team(1).BoxSeat(Blocker1).BoxTimeChange',
        30,
      );
      await waitUntil(
        () => state.team1Blocker1.timeRemaining == const Duration(seconds: 60),
        label: 'server BoxClock update applies the external time change',
      );
    },
    skip: scoreboardVersion() == 'feature-pbt'
        ? false
        : 'Requires katpet/scoreboard feature-pbt BoxSeat protocol',
  );
}

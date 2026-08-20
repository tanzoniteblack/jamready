// Exercises RemoteGameEngine + ScoreboardState directly against a real
// (dockerized) CRG Scoreboard server over a WebSocket, with no Flutter
// widget tree involved. This mirrors the game-flow logic covered by
// integration_test/scoreboard_integration_test.dart but skips app UI/build,
// which is what makes the widget-driven integration tests so slow.
//
// Requires a CRG scoreboard server reachable at SCOREBOARD_HOST:SCOREBOARD_PORT
// (see scripts/test-remote-engine-scoreboards.sh).
import 'package:flutter/services.dart';
import 'package:allure_flutter_test/allure_flutter_test.dart' as allure;
import 'package:allure_flutter_test/flutter_test.dart';

import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/services/remote_game_engine.dart';

import 'utilities/remote_engine_test_helpers.dart';
import 'utilities/scoreboard_operator_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Mock the wakelock channel — RemoteGameEngine.connect()/disconnect()
    // call WakelockPlus.enable()/disable(), which need a channel handler
    // even outside a widget tree. Without this, every test in this file
    // fails on an uncaught PlatformException regardless of its assertions.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (ByteData? message) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  final host = scoreboardHost();
  final port = scoreboardPort();
  final version = scoreboardVersion();

  group('Scoreboard $version', () {
    late ScoreboardState state;
    late RemoteGameEngine engine;
    late ScoreboardOperatorClient operatorClient;

    setUp(() async {
      await allure.parameter('scoreboard_version', version);
      log('--- setUp: connecting engine to ws://$host:$port ---');
      state = ScoreboardState();
      engine = RemoteGameEngine(state);
      await engine.connect('ws://$host:$port');
      await waitUntil(
        () => engine.isConnected,
        timeout: const Duration(seconds: 10),
        label: 'engine connects to scoreboard server',
        debugState: state,
      );
      operatorClient = await ScoreboardOperatorClient.connect(
        operatorWsUri(host, port),
      );
      log('--- setUp complete ---');
    });

    tearDown(() async {
      engine.disconnect();
      await operatorClient.close();
      log('--- tearDown complete ---');
    });

    /// Starts a new game and waits through the pre-game countdown. Disables the
    /// EnforceTimeToOr rule so [ScoreboardOperatorClient.setOfficialScore] isn't
    /// blocked by the 30s timing gate introduced in v2025.9. Returns the game ID.
    Future<String> startGame({String ruleset = 'WFTDARuleset'}) async {
      log('action: startNewGame (ruleset=$ruleset)');
      await operatorClient.startNewGame(
        timeToDerby: const Duration(seconds: 2),
        ruleset: ruleset,
      );
      await waitUntil(
        () => state.gameId.isNotEmpty,
        label: 'game ID populated after StartNewGame',
        debugState: state,
      );
      final gameId = state.gameId;
      log('game ID: $gameId');
      operatorClient.disableOfficialScoreRule(gameId);
      await waitUntil(
        () => !state.clocks['Intermission']!.running,
        timeout: const Duration(seconds: 10),
        label: 'pre-game countdown finishes',
        debugState: state,
      );
      return gameId;
    }

    /// Runs one period: start lineup → start jam → fast-forward period clock
    /// → stop jam.
    /// [scoreTeam1Points], if given, awards team 1 that many points partway
    /// through the jam — the same WS key ("TripScore") a real operator's
    /// scoring button sends, and only effective while a jam is running. Used
    /// to break a 0-0 tie so plain full-game tests end decisively instead of
    /// landing in the overtime-eligible state (see the dedicated "Overtime
    /// transition" test for the tied case).
    Future<void> runPeriod(String gameId, {int? scoreTeam1Points}) async {
      log('action: stopJam (start lineup)');
      await clockAction(() => engine.stopJam()); // "Slide to Start Lineup"
      await waitUntil(
        () => state.clocks['Lineup']!.running,
        label: 'lineup clock starts',
        debugState: state,
      );

      log('action: startJam');
      await clockAction(() => engine.startJam());
      await waitUntil(
        () => state.clocks['Jam']!.running,
        label: 'jam clock starts',
        debugState: state,
      );

      if (scoreTeam1Points != null) {
        log('action: award team 1 $scoreTeam1Points points via TripScore');
        operatorClient.addTripScore(gameId, 1, scoreTeam1Points);
        await waitUntil(
          () => state.team1.score == scoreTeam1Points,
          label: 'team 1 score reflects awarded points',
          debugState: state,
        );
      }

      log('action: fast-forward Period clock to 0');
      operatorClient.setClockTime(gameId, 'Period', 0);
      // Wait for the server to round-trip the Period clock update before
      // ending the jam — otherwise stopJam can race ahead of the update and
      // the server won't recognize the period has ended (it'll advance to
      // Lineup instead of Intermission).
      await waitUntil(
        () => state.clocks['Period']!.time <= 0,
        label: 'Period clock reflects fast-forward to 0',
        debugState: state,
      );

      log('action: stopJam (end jam)');
      await clockAction(() => engine.stopJam());
      await waitUntil(
        () => !state.clocks['Jam']!.running,
        label: 'jam clock stops',
        debugState: state,
      );
    }

    /// Advances through an intermission by fast-forwarding its clock, then
    /// waits for the game to be ready for the next period.
    Future<void> runIntermission(String gameId) async {
      await waitUntil(
        () => state.clocks['Intermission']!.running,
        label: 'intermission clock starts',
        debugState: state,
      );
      log('action: fast-forward Intermission clock to 0');
      operatorClient.setClockTime(gameId, 'Intermission', 0);
      await waitUntil(
        () => !state.clocks['Intermission']!.running,
        label: 'intermission clock finishes',
        debugState: state,
      );
    }

    /// Confirms the official score and waits for it to be reflected in state.
    Future<void> finishGame(String gameId) async {
      await waitUntil(
        () => !state.inJam && !state.clocks['Lineup']!.running,
        label: 'post-game unofficial score state reached',
        debugState: state,
      );

      // The server enforces a real delay before OfficialScore can be set
      // (Rule.LINEUP_DURATION, 30s default), regardless of EnforceTimeToOr.
      log('waiting 32s for InhibitFinalScore to clear before confirming score');
      await Future.delayed(const Duration(seconds: 32));

      log('action: setOfficialScore');
      operatorClient.setOfficialScore(gameId);
      await waitUntil(
        () => state.officialScore,
        label: 'official score confirmed',
        debugState: state,
      );
    }

    test('Jam, lineup, and undo control flow', () async {
      await operatorClient.startNewGame();
      await waitUntil(
        () => state.gameId.isNotEmpty,
        label: 'game ID populated',
        debugState: state,
      );

      // Pre-game: no undo action available yet.
      await waitUntil(
        () => !state.hasUndoAction,
        timeout: const Duration(seconds: 10),
        label: 'no undo action available pre-game',
        debugState: state,
      );

      log('action: stopJam (start lineup)');
      await clockAction(() => engine.stopJam()); // "Slide to Start Lineup"
      await waitUntil(
        () =>
            state.clocks['Lineup']!.running &&
            !state.clocks['Jam']!.running &&
            !state.clocks['Period']!.running,
        timeout: const Duration(seconds: 20),
        label: 'lineup clock starts and jam/period clocks stay stopped',
        debugState: state,
      );

      log('action: startJam');
      await clockAction(() => engine.startJam());
      await waitUntil(
        () => state.clocks['Jam']!.running && state.clocks['Period']!.running,
        timeout: const Duration(seconds: 20),
        label: 'jam and period clocks start',
        debugState: state,
      );

      // Undo (unstart jam) → should return to lineup.
      await waitUntil(
        () => state.hasUndoAction,
        label: 'undo action becomes available',
        debugState: state,
      );
      log('action: undo');
      engine.undo();
      await waitUntil(
        () => state.clocks['Lineup']!.running && !state.clocks['Jam']!.running,
        timeout: const Duration(seconds: 20),
        label: 'undo returns to lineup',
        debugState: state,
      );

      // Start the jam again, then stop it — should end the jam and start the
      // next lineup.
      log('action: startJam');
      await clockAction(() => engine.startJam());
      await waitUntil(
        () => state.clocks['Jam']!.running,
        timeout: const Duration(seconds: 20),
        label: 'jam clock starts',
        debugState: state,
      );

      log('action: stopJam (end jam)');
      await clockAction(() => engine.stopJam());
      await waitUntil(
        () => !state.clocks['Jam']!.running && state.clocks['Lineup']!.running,
        timeout: const Duration(seconds: 20),
        label: 'jam clock stops and lineup clock starts',
        debugState: state,
      );

      // Undo is now available and carries a real label from the server (not
      // the "no action" sentinel).
      await waitUntil(
        () => state.hasUndoAction,
        timeout: const Duration(seconds: 10),
        label: 'undo action becomes available',
        debugState: state,
      );
      expect(state.labelUndo, isNot(anyOf('No Action', '---')));
    });

    test(
      'Timeout flow highlights controls, decrements review counts, and undo restores timeout',
      () async {
        await operatorClient.startNewGame();
        await waitUntil(
          () => state.gameId.isNotEmpty,
          label: 'game ID populated',
          debugState: state,
        );

        log('action: stopJam (start lineup)');
        await clockAction(() => engine.stopJam()); // start lineup
        await waitUntil(
          () => state.clocks['Lineup']!.running,
          label: 'lineup clock starts',
          debugState: state,
        );

        // Start a jam before calling timeout: review-count decrementing only
        // takes effect once a jam has actually run this period.
        log('action: startJam');
        await clockAction(() => engine.startJam());
        await waitUntil(
          () =>
              state.team1.serverId.isNotEmpty &&
              state.team2.serverId.isNotEmpty,
          timeout: const Duration(seconds: 20),
          label: 'team server IDs populated',
          debugState: state,
        );

        // Verify initial OR count for WFTDA (1 per team per period).
        expect(state.team1.officialReviews, 1);
        expect(state.team2.officialReviews, 1);

        log('action: startTimeout');
        await clockAction(() => engine.startTimeout());
        await waitUntil(
          () => state.clocks['Timeout']!.running,
          timeout: const Duration(seconds: 20),
          label: 'timeout clock starts',
          debugState: state,
        );

        log('action: setTimeoutOwner(1)');
        engine.setTimeoutOwner('1');
        await waitUntil(
          () =>
              state.timeoutOwner == state.team1.serverId &&
              !state.isOfficialReview,
          label: 'timeout owner becomes team 1',
          debugState: state,
        );

        log('action: setTimeoutOwner(2)');
        engine.setTimeoutOwner('2');
        await waitUntil(
          () =>
              state.timeoutOwner == state.team2.serverId &&
              !state.isOfficialReview,
          label: 'timeout owner becomes team 2',
          debugState: state,
        );

        log('action: setTimeoutOwner(O)');
        engine.setTimeoutOwner('O');
        await waitUntil(
          () => state.timeoutOwner == 'O',
          label: 'timeout owner becomes official',
          debugState: state,
        );

        log('action: setTimeoutOwner(1, isOfficialReview: true)');
        engine.setTimeoutOwner('1', isOfficialReview: true);
        // The owner/review-mode fields and the review-count field can arrive
        // in separate state messages, so wait for the count too rather than
        // asserting immediately after the owner/review-mode condition.
        await waitUntil(
          () =>
              state.timeoutOwner == state.team1.serverId &&
              state.isOfficialReview &&
              state.team1.officialReviews == 0,
          label:
              'official review owner becomes team 1 and its count decrements',
          debugState: state,
        );

        log('action: setTimeoutOwner(2, isOfficialReview: true)');
        engine.setTimeoutOwner('2', isOfficialReview: true);
        await waitUntil(
          () =>
              state.timeoutOwner == state.team2.serverId &&
              state.isOfficialReview &&
              state.team2.officialReviews == 0,
          label:
              'official review owner becomes team 2 and its count decrements',
          debugState: state,
        );

        log('action: endTimeout');
        await clockAction(() => engine.endTimeout());
        await waitUntil(
          () => state.clocks['Lineup']!.running,
          timeout: const Duration(seconds: 20),
          label: 'lineup clock resumes after timeout',
          debugState: state,
        );

        await waitUntil(
          () => state.hasUndoAction,
          label: 'undo action becomes available',
          debugState: state,
        );

        log('action: undo');
        engine.undo();

        await waitUntil(
          () => state.clocks['Timeout']!.running,
          timeout: const Duration(seconds: 20),
          label: 'timeout clock restored by undo',
          debugState: state,
        );
      },
    );

    test(
      'Full game start/stop',
      () async {
        final gameId = await startGame();

        log('--- period 1 ---');
        await runPeriod(gameId, scoreTeam1Points: 4);
        await runIntermission(gameId);

        log('--- period 2 (final) ---');
        await runPeriod(gameId);
        await finishGame(gameId);
      },
      // finishGame's 32s wait for InhibitFinalScore to clear pushes this past
      // package:test's default 30s per-test timeout.
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'Full game start/stop - RDCL',
      () async {
        final gameId = await startGame(ruleset: 'RDCLRuleset');

        log('--- period 1 ---');
        await runPeriod(gameId, scoreTeam1Points: 4);
        await runIntermission(gameId); // 5 min

        log('--- period 2 ---');
        await runPeriod(gameId);
        await runIntermission(gameId); // 15 min

        log('--- period 3 ---');
        await runPeriod(gameId);
        await runIntermission(gameId); // 5 min

        log('--- period 4 (final) ---');
        await runPeriod(gameId);
        // Official-score confirmation itself (finishGame) is covered by the
        // WFTDA test above and isn't ruleset-specific - skip its 32s wait
        // here and just confirm the game reaches the post-game state.
        await waitUntil(
          () => !state.inJam && !state.clocks['Lineup']!.running,
          label: 'post-game unofficial score state reached',
          debugState: state,
        );
      },
      // RDCL runs 4 periods (vs. WFTDA's 2); package:test's default 30s
      // per-test timeout can race ahead of our own waitUntil timeouts before
      // all 4 periods + intermissions finish.
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'Overtime transition on tied game',
      () async {
        // Games started with 0-0 scores are tied, so the server will offer
        // overtime after the final period via Label(Stop) = "Overtime Lineup".
        final gameId = await startGame();

        log('--- period 1 ---');
        await runPeriod(gameId);
        await runIntermission(gameId);

        log('--- period 2 (final) — scores remain tied at 0-0 ---');
        await runPeriod(gameId);

        await waitUntil(
          () => !state.inJam && !state.clocks['Lineup']!.running,
          label: 'post-game unofficial score state reached',
          debugState: state,
        );

        // The server signals overtime availability via Label(Stop).
        await waitUntil(
          () => state.labelStop.toLowerCase().contains('overtime'),
          timeout: const Duration(seconds: 20),
          label: 'server signals overtime availability via Label(Stop)',
          debugState: state,
        );

        // Confirming the "Overtime Lineup" swipe button calls stopJam().
        log('action: stopJam (confirm overtime lineup)');
        await clockAction(() => engine.stopJam());

        await waitUntil(
          () => state.clocks['Lineup']!.running,
          timeout: const Duration(seconds: 20),
          label: 'overtime lineup clock starts',
          debugState: state,
        );
      },
      skip: versionAtLeast(version, 2025, 4)
          ? false
          : 'Overtime signaling requires v2025.4+',
    );
  });
}

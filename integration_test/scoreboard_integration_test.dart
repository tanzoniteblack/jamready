import 'dart:convert';
import 'dart:io';

// The Allure Flutter drop-in writes from the Android test process, where its
// default results directory is read-only. The runner captures Flutter's
// host-side JSON stream and converts it to Allure results instead.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:jam_ready/main.dart' as app;
import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/screens/jam_timer_screen.dart';
import 'package:jam_ready/widgets/swipe_button.dart';

import 'utilities/common_helpers.dart';

/// The CRG server's `GameImpl.quickClockControl()` treats two Start/Stop/
/// Timeout button presses within 1000ms of each other as an accidental
/// double-click: same button -> silently dropped; different button -> the
/// previous action is silently undone and replaced. There's no visible
/// signal when this happens (no error, no rejected message) - it just
/// quietly corrupts game state. `tapJamControl` already guards against this
/// via [JamControls.cooldownDuration] (3s) before every tap, but
/// `swipeToStartLineup` and the overtime confirmation swipe below both send
/// a Stop-button action directly without going through that cooldown. Call
/// this immediately before either to guarantee the 1s window has passed.
const _clockActionCooldown = Duration(seconds: 2);
void _ensureClockActionCooldown() {
  sleep(_clockActionCooldown);
}

class ScoreboardTestClient {
  ScoreboardTestClient(this._channel);

  final WebSocketChannel _channel;

  static Future<ScoreboardTestClient> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return ScoreboardTestClient(channel);
  }

  Future<void> startNewGame({
    Duration? timeToDerby,
    String ruleset = 'WFTDARuleset',
  }) async {
    _channel.sink.add(
      jsonEncode({
        'action': 'Register',
        'paths': ['ScoreBoard.CurrentGame.Game'],
      }),
    );
    final message = {
      'action': 'StartNewGame',
      'data': {
        'Team1': '',
        'Team2': '',
        'Ruleset': ruleset,
        'IntermissionClock': timeToDerby != null
            ? '${timeToDerby.inMilliseconds}'
            : null,
        'Advance': false,
        'Points1': 0,
        'Points2': 0,
        'TO1': 0,
        'TO2': 0,
        'OR1': 0,
        'OR2': 0,
        'Period': 0,
        'Jam': 0,
        'PeriodClock': '0',
      },
    };

    _channel.sink.add(jsonEncode(message));
    // give the server a few seconds to actually get going
    sleep(Duration(seconds: 2));
  }

  /// Sets a clock time on the server
  void setClockTime(String gameId, String clockName, int timeMs) {
    _channel.sink.add(
      jsonEncode({
        'action': 'Set',
        'key': 'ScoreBoard.Game($gameId).Clock($clockName).Time',
        'value': timeMs.toString(),
        'flag': '',
      }),
    );
  }

  void disableOfficialScoreRule(String gameId) {
    // v2025.9+ enforces a timing gate (INHIBIT_FINAL_SCORE) before OfficialScore
    // can be set. Disable the rule so tests don't have to wait 30s after final
    // jam end.
    _channel.sink.add(
      jsonEncode({
        "action": "Set",
        "key": "ScoreBoard.Game($gameId).Rule(Score.EnforceTimeToOr)",
        "value": "false",
        "flag": "",
      }),
    );
  }

  void setOfficialScore(String gameId) {
    _channel.sink.add(
      jsonEncode({
        "action": "Set",
        "key": "ScoreBoard.Game($gameId).OfficialScore",
        "value": true,
        "flag": "",
      }),
    );
  }

  Future<void> close() async {
    await _channel.sink.close();
  }
}

Uri _scoreboardWsUri(String host, int port) {
  final base = Uri.parse('ws://$host:$port');
  print('Connecting to: $base');
  return base.replace(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    path: '/WS/',
    queryParameters: const {'source': 'integration', 'platform': 'test'},
  );
}

String _scoreboardHost() {
  const host = String.fromEnvironment('SCOREBOARD_HOST');
  return host.isNotEmpty ? host : '192.168.0.115'; //'ryan.local';
}

int _scoreboardPort() {
  const port = String.fromEnvironment('SCOREBOARD_PORT');
  return int.tryParse(port) ?? 8000;
}

String _scoreboardVersion() {
  const version = String.fromEnvironment('SCOREBOARD_VERSION');
  return version; // empty string means unknown / not provided
}

/// Returns true if the scoreboard version is at least [major].[minor].
/// An unknown version (empty string) is treated as compatible.
bool _versionAtLeast(String version, int major, int minor) {
  if (version.isEmpty) return true;
  final stripped = version.startsWith('v') ? version.substring(1) : version;
  final parts = stripped.split('.');
  final ma = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final mi = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return ma > major || (ma == major && mi >= minor);
}

Future<ScoreboardTestClient> _launchAppAndConnect(WidgetTester tester) async {
  final host = _scoreboardHost();
  final port = _scoreboardPort();

  SharedPreferences.setMockInitialValues({});

  app.main();
  // The app opens on the role picker. Choose the timer flow before looking
  // for its remote-scoreboard settings.
  await tester.pump(const Duration(seconds: 1));
  await pumpUntil(
    tester,
    () => find.text('Jam Timer Operator').evaluate().isNotEmpty,
    timeout: const Duration(seconds: 10),
  );
  await tester.tap(find.text('Jam Timer Operator'));

  // Wait for the timer settings screen to be visible after navigation.
  await pumpUntil(
    tester,
    () => find
        .widgetWithText(TextFormField, 'Host / IP Address')
        .evaluate()
        .isNotEmpty,
    timeout: const Duration(seconds: 10),
  );

  // Find and fill in the host field
  final hostField = find.widgetWithText(TextFormField, 'Host / IP Address');
  await tester.enterText(hostField, host);
  await tester.pump();

  // Find and fill in the port field
  final portField = find.widgetWithText(TextFormField, 'Port');
  await tester.enterText(portField, port.toString());
  await tester.pump();

  // Tap the CONNECT button
  final connectButton = find.text('START REMOTE SESSION');
  await tester.tap(connectButton);
  await tester.pump(const Duration(seconds: 1));

  // Wait for navigation to JamTimerScreen and connection
  await pumpUntil(
    tester,
    () => find.byType(JamTimerScreen).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 10),
  );

  await pumpUntil(
    tester,
    () => scoreboardState(tester).isConnected,
    timeout: const Duration(seconds: 30),
  );

  return ScoreboardTestClient.connect(_scoreboardWsUri(host, port));
}

Future<void> _ensureSwipeToLineup(WidgetTester tester) async {
  await pumpUntil(
    tester,
    () => find
        .ancestor(
          of: find.text('SLIDE TO START LINEUP'),
          matching: find.byType(SwipeButton),
        )
        .evaluate()
        .isNotEmpty,
    timeout: const Duration(seconds: 15),
  );
}

bool _isOfficialReview(ScoreboardState state) => state.isOfficialReview;

Future<void> _waitForTeamServerIds(WidgetTester tester) async {
  await pumpUntil(tester, () {
    final state = scoreboardState(tester);
    return state.team1.serverId.isNotEmpty && state.team2.serverId.isNotEmpty;
  });
}

Future<void> _waitForTimeoutMode(WidgetTester tester) async {
  await pumpUntil(tester, () {
    final state = scoreboardState(tester);
    return state.clocks['Timeout']!.running || state.inTimeout;
  }, timeout: const Duration(seconds: 20));
}

Future<void> _swipeUndoButton(WidgetTester tester) async {
  // Find the undo SwipeButton - it should contain "Undo:" in its label
  // This should be the second SwipeButton on screen (after Start Lineup)
  final buttons = find.byType(SwipeButton);
  print('Found ${buttons.evaluate().length} swipe button(s) for undo');

  // Wait for undo action to become available
  await pumpUntil(tester, () => scoreboardState(tester).hasUndoAction);

  // In connected mode with undo available, we should have 2 buttons
  // The undo button should be the last one (or we can find by ancestor)
  expect(
    buttons,
    findsAtLeast(1),
    reason: 'Should have at least one SwipeButton',
  );

  // Get the last SwipeButton which should be the undo
  final buttonList = buttons.evaluate().toList();
  final undoButton = find.byWidget(buttonList.last.widget);

  await swipeButton(tester, undoButton);
}

/// Starts a new game, waits through the pre-game countdown, and returns the
/// game ID. Disables the EnforceTimeToOr rule so [setOfficialScore] is not
/// blocked by the 30s timing gate introduced in v2025.9.
Future<String> _startGame(
  WidgetTester tester,
  ScoreboardTestClient client, {
  String ruleset = 'WFTDARuleset',
}) async {
  await client.startNewGame(
    timeToDerby: const Duration(seconds: 4),
    ruleset: ruleset,
  );
  await validateActiveDisplay(tester, ActiveDisplay.timeToDerby);
  await validateActiveDisplay(
    tester,
    ActiveDisplay.ready,
    timeout: const Duration(seconds: 4),
  );
  final gameId = scoreboardState(tester).gameId;
  client.disableOfficialScoreRule(gameId);
  return gameId;
}

/// Runs one period: swipe to lineup → start jam → fast-forward period clock
/// → stop jam.
Future<void> _runPeriod(
  WidgetTester tester,
  ScoreboardTestClient client,
  String gameId,
) async {
  // Unlike tapJamControl, swipeToStartLineup doesn't wait out
  // JamControls.cooldownDuration first. On a second-or-later period this
  // Stop-button press can land within 1s of the previous period's final
  // tapJamControl(stop), tripping the server's quick-click debounce - see
  // _ensureClockActionCooldown above.
  _ensureClockActionCooldown();
  await swipeToStartLineup(tester);
  await validateActiveDisplay(tester, ActiveDisplay.lineup);

  await tapJamControl(tester, scoreboardState(tester).labelStart);
  await validateActiveDisplay(tester, ActiveDisplay.jam);

  client.setClockTime(gameId, 'Period', 0);
  await validateActiveDisplay(tester, ActiveDisplay.jam);

  await tapJamControl(tester, scoreboardState(tester).labelStop);
}

/// Advances through an intermission: validates the intermission display,
/// fast-forwards the intermission clock, then waits for the ready display.
Future<void> _runIntermission(
  WidgetTester tester,
  ScoreboardTestClient client,
  String gameId,
) async {
  await validateActiveDisplay(tester, ActiveDisplay.intermission);
  client.setClockTime(gameId, 'Intermission', 0);
  await validateActiveDisplay(tester, ActiveDisplay.ready);
  // Brief pause for server to process the period transition.
  sleep(const Duration(seconds: 3));
}

/// Validates the unofficial score display, sets the official score, then
/// waits for the game over display.
Future<void> _finishGame(
  WidgetTester tester,
  ScoreboardTestClient client,
  String gameId,
) async {
  await validateActiveDisplay(tester, ActiveDisplay.unofficialScore);
  client.setOfficialScore(gameId);
  await validateActiveDisplay(tester, ActiveDisplay.gameOver);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Jam, lineup, and undo control flow', (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensureSwipeToLineup(tester);

    // Pre-game: no undo action available yet.
    await pumpUntil(
      tester,
      () => !scoreboardState(tester).hasUndoAction,
      timeout: const Duration(seconds: 10),
    );
    expect(
      find.textContaining('NO UNDO AVAILABLE'),
      findsOneWidget,
      reason: 'Should show NO UNDO AVAILABLE when no action',
    );

    // Swiping to start lineup starts the lineup clock only.
    await swipeToStartLineup(tester);
    await pumpUntil(tester, () {
      final state = scoreboardState(tester);
      return state.clocks['Lineup']!.running &&
          !state.clocks['Jam']!.running &&
          !state.clocks['Period']!.running;
    }, timeout: const Duration(seconds: 20));
    await validateActiveDisplay(tester, .lineup);

    // Starting a jam starts the jam and period clocks.
    await tapJamControl(tester, scoreboardState(tester).labelStart);
    await pumpUntil(tester, () {
      final state = scoreboardState(tester);
      return state.clocks['Jam']!.running && state.clocks['Period']!.running;
    }, timeout: const Duration(seconds: 20));
    await validateActiveDisplay(tester, .jam);

    // Undo (unstart jam) → should return to lineup.
    await _swipeUndoButton(tester);
    await pumpUntil(tester, () {
      final state = scoreboardState(tester);
      return state.clocks['Lineup']!.running && !state.clocks['Jam']!.running;
    }, timeout: const Duration(seconds: 20));
    await validateActiveDisplay(tester, ActiveDisplay.lineup);

    // Start the jam again, then stop it — should end the jam and start
    // the next lineup.
    await tapJamControl(tester, scoreboardState(tester).labelStart);
    await pumpUntil(
      tester,
      () => scoreboardState(tester).clocks['Jam']!.running,
      timeout: const Duration(seconds: 20),
    );
    await validateActiveDisplay(tester, .jam);

    await tapJamControl(tester, scoreboardState(tester).labelStop);
    await pumpUntil(tester, () {
      final state = scoreboardState(tester);
      return !state.clocks['Jam']!.running && state.clocks['Lineup']!.running;
    }, timeout: const Duration(seconds: 20));
    await validateActiveDisplay(tester, .lineup);

    // Undo is now available and shows the real action label from the
    // server (not the "no action" sentinel).
    await pumpUntil(
      tester,
      () => scoreboardState(tester).hasUndoAction,
      timeout: const Duration(seconds: 10),
    );
    final undoLabel = scoreboardState(tester).labelUndo;
    expect(
      find.textContaining(undoLabel.toUpperCase()),
      findsAtLeast(1),
      reason: 'Undo label "$undoLabel" should be visible on screen',
    );
  });

  testWidgets(
    'Timeout flow highlights controls, decrements review counts, and undo restores timeout',
    (tester) async {
      final client = await _launchAppAndConnect(tester);
      addTearDown(client.close);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      await client.startNewGame();
      await _ensureSwipeToLineup(tester);
      await swipeToStartLineup(tester);
      // Start a jam before calling timeout: review-count decrementing
      // only takes effect once a jam has actually run this period.
      await tapJamControl(tester, scoreboardState(tester).labelStart);
      await pumpUntil(
        tester,
        () => scoreboardState(tester).clocks['Jam']!.running,
        timeout: const Duration(seconds: 20),
      );
      await _waitForTeamServerIds(tester);

      await tapJamControl(tester, scoreboardState(tester).labelTimeout);
      await _waitForTimeoutMode(tester);
      await pumpUntil(
        tester,
        () => scoreboardState(tester).clocks['Timeout']!.running,
        timeout: const Duration(seconds: 20),
      );

      // Find timeout menu buttons by their InkWell widgets containing the text
      // The new menu uses custom InkWell buttons with uppercase text
      final timeoutButtons = find.widgetWithText(InkWell, 'TIMEOUT');
      final reviewButtons = find.widgetWithText(InkWell, 'REVIEW');
      final officialTimeoutButton = find.widgetWithText(
        InkWell,
        'OFFICIAL TIMEOUT',
      );

      await pumpUntil(
        tester,
        () =>
            timeoutButtons.evaluate().length >= 2 &&
            reviewButtons.evaluate().length >= 2 &&
            officialTimeoutButton.evaluate().isNotEmpty,
      );

      // Verify initial OR count for WFTDA (1 per team per period).
      expect(scoreboardState(tester).team1.officialReviews, 1);
      expect(scoreboardState(tester).team2.officialReviews, 1);

      await tester.tap(timeoutButtons.first);
      await tester.pump();
      await pumpUntil(tester, () {
        final state = scoreboardState(tester);
        return state.timeoutOwner == state.team1.serverId &&
            !_isOfficialReview(state);
      });

      await tester.tap(timeoutButtons.at(1));
      await tester.pump();
      await pumpUntil(tester, () {
        final state = scoreboardState(tester);
        return state.timeoutOwner == state.team2.serverId &&
            !_isOfficialReview(state);
      });

      await tester.tap(officialTimeoutButton);
      await tester.pump();
      await pumpUntil(
        tester,
        () => scoreboardState(tester).timeoutOwner == 'O',
      );

      await tester.tap(reviewButtons.first); // assign team 1 official review
      await tester.pump();
      // The owner/review-mode fields and the review-count field can arrive
      // in separate state messages, so wait for the count too rather than
      // asserting immediately after the owner/review-mode condition.
      await pumpUntil(tester, () {
        final state = scoreboardState(tester);
        return state.timeoutOwner == state.team1.serverId &&
            _isOfficialReview(state) &&
            state.team1.officialReviews == 0;
      });

      await tester.tap(reviewButtons.at(1)); // assign team 2 official review
      await tester.pump();
      await pumpUntil(tester, () {
        final state = scoreboardState(tester);
        return state.timeoutOwner == state.team2.serverId &&
            _isOfficialReview(state) &&
            state.team2.officialReviews == 0;
      });
      // Team 2 review count must have decremented from 1 → 0.
      expect(scoreboardState(tester).team2.officialReviews, 0);

      final endTimeoutButton = find.widgetWithText(InkWell, 'END TIMEOUT');
      await tester.ensureVisible(endTimeoutButton);
      await tester.tap(endTimeoutButton);
      await tester.pump();
      await pumpUntil(tester, () {
        final state = scoreboardState(tester);
        return state.clocks['Lineup']!.running;
      }, timeout: const Duration(seconds: 20));

      // Wait for undo action to be available
      await pumpUntil(tester, () => scoreboardState(tester).hasUndoAction);

      // Swipe the undo button to restore timeout
      await _swipeUndoButton(tester);

      await pumpUntil(
        tester,
        () => scoreboardState(tester).clocks['Timeout']!.running,
        timeout: const Duration(seconds: 20),
      );
    },
  );

  testWidgets('Full game start/stop', (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    final gameId = await _startGame(tester, client);

    // Period 1
    await _runPeriod(tester, client, gameId);
    await _runIntermission(tester, client, gameId);

    // Period 2 (final)
    await _runPeriod(tester, client, gameId);
    await _finishGame(tester, client, gameId);
  });

  testWidgets('Full game start/stop - RDCL', (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    final gameId = await _startGame(tester, client, ruleset: 'RDCLRuleset');

    // Period 1
    await _runPeriod(tester, client, gameId);
    await _runIntermission(tester, client, gameId); // 5 min

    // Period 2
    await _runPeriod(tester, client, gameId);
    await _runIntermission(tester, client, gameId); // 15 min

    // Period 3
    await _runPeriod(tester, client, gameId);
    await _runIntermission(tester, client, gameId); // 5 min

    // Period 4 (final)
    await _runPeriod(tester, client, gameId);
    await _finishGame(tester, client, gameId);
  });

  testWidgets(
    'Overtime transition on tied game',
    skip: !_versionAtLeast(_scoreboardVersion(), 2025, 4),
    (tester) async {
      final client = await _launchAppAndConnect(tester);
      addTearDown(client.close);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });

      // Games started with 0-0 scores are tied, so the server will offer
      // overtime after the final period via Label(Stop) = "Overtime Lineup".
      final gameId = await _startGame(tester, client);

      // Period 1
      await _runPeriod(tester, client, gameId);
      await _runIntermission(tester, client, gameId);

      // Period 2 (final) — scores remain tied at 0-0
      await _runPeriod(tester, client, gameId);

      await validateActiveDisplay(tester, ActiveDisplay.unofficialScore);

      // The purple overtime SwipeButton appears once Label(Stop) signals overtime.
      final overtimeButton = find.ancestor(
        of: find.textContaining('OVERTIME LINEUP'),
        matching: find.byType(SwipeButton),
      );
      await pumpUntil(
        tester,
        () => overtimeButton.evaluate().isNotEmpty,
        timeout: const Duration(seconds: 5),
      );

      // This swipe sends the same Stop-button action as the final
      // tapJamControl(stop) above, without tapJamControl's cooldown wait.
      // Same button within 1s of itself trips the server's quick-click
      // debounce and gets silently dropped - see _ensureClockActionCooldown.
      // Kept at 5s (rather than the 2s default) since this is the exact
      // transition that was observed to flake.
      sleep(const Duration(seconds: 5));

      await swipeButton(tester, overtimeButton.first);
      await validateActiveDisplay(
        tester,
        ActiveDisplay.lineup,
        timeout: Duration(seconds: 5),
      );
    },
  );
}

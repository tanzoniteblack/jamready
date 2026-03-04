import 'dart:convert';
import 'dart:io';
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

Future<ScoreboardTestClient> _launchAppAndConnect(WidgetTester tester) async {
  final host = _scoreboardHost();
  final port = _scoreboardPort();

  SharedPreferences.setMockInitialValues({});

  app.main();
  // Wait for the settings screen to appear
  await tester.pump(const Duration(seconds: 1));

  // Wait for settings screen to be visible
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

  testWidgets('Slide to start lineup starts lineup only', (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensureSwipeToLineup(tester);

    await swipeToStartLineup(tester);

    await pumpUntil(tester, () {
      final state = scoreboardState(tester);
      return state.clocks['Lineup']!.running &&
          !state.clocks['Jam']!.running &&
          !state.clocks['Period']!.running;
    }, timeout: const Duration(seconds: 20));

    await validateActiveDisplay(tester, .lineup);
  });

  testWidgets('Starting initial jam starts jam and period clocks', (
    tester,
  ) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensureSwipeToLineup(tester);
    await swipeToStartLineup(tester);
    await tapJamControl(tester, scoreboardState(tester).labelStart);
    await pumpUntil(tester, () {
      final state = scoreboardState(tester);
      return state.clocks['Jam']!.running && state.clocks['Period']!.running;
    }, timeout: const Duration(seconds: 20));

    await validateActiveDisplay(tester, .jam);
  });

  testWidgets('Stop jam ends jam and starts lineup', (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensureSwipeToLineup(tester);
    await swipeToStartLineup(tester);
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
  });

  testWidgets('Timeout flow highlights controls and undo restores timeout', (
    tester,
  ) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensureSwipeToLineup(tester);
    await swipeToStartLineup(tester);
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
    await pumpUntil(tester, () => scoreboardState(tester).timeoutOwner == 'O');

    await tester.tap(reviewButtons.first);
    await tester.pump();
    await pumpUntil(tester, () {
      final state = scoreboardState(tester);
      return state.timeoutOwner == state.team1.serverId &&
          _isOfficialReview(state);
    });

    await tester.tap(reviewButtons.at(1));
    await tester.pump();
    await pumpUntil(tester, () {
      final state = scoreboardState(tester);
      return state.timeoutOwner == state.team2.serverId &&
          _isOfficialReview(state);
    });

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
  });

  testWidgets('Undo SwipeButton shows No Undo Available when disabled', (
    tester,
  ) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensureSwipeToLineup(tester);

    // Verify we're in pre-game state with no undo available.
    await pumpUntil(
      tester,
      () => !scoreboardState(tester).hasUndoAction,
      timeout: const Duration(seconds: 10),
    );

    // Find the undo SwipeButton - it should show "No Undo Available"
    // In remote mode, there should be 2 SwipeButtons: Start Lineup and Undo
    final buttons = find.byType(SwipeButton);
    await pumpUntil(
      tester,
      () => buttons.evaluate().length >= 2,
      timeout: const Duration(seconds: 10),
    );

    // Check that the undo button text is visible
    expect(
      find.textContaining('NO UNDO AVAILABLE'),
      findsOneWidget,
      reason: 'Should show NO UNDO AVAILABLE when no action',
    );
  });

  testWidgets('Undo SwipeButton shows action label when available', (
    tester,
  ) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensureSwipeToLineup(tester);
    await swipeToStartLineup(tester);

    // Wait for lineup to start
    await pumpUntil(
      tester,
      () => scoreboardState(tester).clocks['Lineup']!.running,
      timeout: const Duration(seconds: 20),
    );

    // Start a jam
    await tapJamControl(tester, scoreboardState(tester).labelStart);

    // Wait for jam to start
    await pumpUntil(
      tester,
      () => scoreboardState(tester).clocks['Jam']!.running,
      timeout: const Duration(seconds: 20),
    );

    // Stop the jam
    await tapJamControl(tester, scoreboardState(tester).labelStop);

    // Wait for lineup to start (after jam stop)
    await pumpUntil(
      tester,
      () => scoreboardState(tester).clocks['Lineup']!.running,
      timeout: const Duration(seconds: 20),
    );

    // Wait for undo action to become available.
    await pumpUntil(
      tester,
      () => scoreboardState(tester).hasUndoAction,
      timeout: const Duration(seconds: 10),
    );

    // Verify the undo button shows the action label from state.
    // SwipeButton renders its label in uppercase.
    expect(scoreboardState(tester).hasUndoAction, isTrue);
    final undoLabel = scoreboardState(tester).labelUndo;
    expect(
      find.textContaining(undoLabel.toUpperCase()),
      findsAtLeast(1),
      reason: 'Undo label "$undoLabel" should be visible on screen',
    );
  });

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
}

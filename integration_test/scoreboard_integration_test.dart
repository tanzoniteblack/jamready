import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:jam_ready/main.dart' as app;
import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/screens/jam_timer_screen.dart';
import 'package:jam_ready/widgets/jam_controls.dart';
import 'package:jam_ready/widgets/swipe_button.dart';

class ScoreboardTestClient {
  ScoreboardTestClient(this._channel);

  final WebSocketChannel _channel;

  static Future<ScoreboardTestClient> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return ScoreboardTestClient(channel);
  }

  Future<void> startNewGame() async {
    _channel.sink.add(jsonEncode({
      'action': 'Register',
      'paths': ['ScoreBoard.CurrentGame.Game'],
    }));
    final message = {
      'action': 'StartNewGame',
      'data': {
        'Team1': '',
        'Team2': '',
        'Ruleset': 'WFTDARuleset',
        'IntermissionClock': null,
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
    _channel.sink.add(jsonEncode({
      'action': 'Set',
      'key': 'ScoreBoard.Game($gameId).Clock($clockName).Time',
      'value': timeMs.toString(),
      'flag': '',
    }));
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
  return host.isNotEmpty ? host : '192.168.0.111'; //'ryan.local';
}

int _scoreboardPort() {
  const port = String.fromEnvironment('SCOREBOARD_PORT');
  return int.tryParse(port) ?? 8001;
}

ScoreboardState _state(WidgetTester tester) {
  final context = tester.element(find.byType(JamTimerScreen));
  return Provider.of<ScoreboardState>(context, listen: false);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(step);
    if (condition()) return;
  }
  throw TestFailure('Timed out waiting for condition.');
}

Future<ScoreboardTestClient> _launchAppAndConnect(
  WidgetTester tester,
) async {
  final host = _scoreboardHost();
  final port = _scoreboardPort();

  SharedPreferences.setMockInitialValues({});

  app.main();
  // Wait for the settings screen to appear
  await tester.pump(const Duration(seconds: 1));

  // Wait for settings screen to be visible
  await _pumpUntil(
    tester,
    () => find.text('SETTINGS').evaluate().isNotEmpty,
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
  final connectButton = find.text('CONNECT');
  await tester.tap(connectButton);
  await tester.pump(const Duration(seconds: 1));

  // Wait for navigation to JamTimerScreen and connection
  await _pumpUntil(
    tester,
    () => find.byType(JamTimerScreen).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 10),
  );

  await _pumpUntil(
    tester,
    () => _state(tester).isConnected,
    timeout: const Duration(seconds: 30),
  );

  return ScoreboardTestClient.connect(_scoreboardWsUri(host, port));
}

Future<void> _ensurePrePeriod(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () => find.byType(SwipeButton).evaluate().isNotEmpty,
    timeout: const Duration(seconds: 15),
  );
}

bool _isOfficialReview(ScoreboardState state) => state.isOfficialReview;

Future<void> _waitForTeamServerIds(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () {
      final state = _state(tester);
      return state.team1.serverId.isNotEmpty &&
          state.team2.serverId.isNotEmpty;
    },
  );
}

Future<void> _waitForTimeoutMode(WidgetTester tester) async {
  await _pumpUntil(
    tester,
    () {
      final state = _state(tester);
      return state.clocks['Timeout']!.running || state.inTimeout;
    },
    timeout: const Duration(seconds: 20),
  );
}

Future<void> _swipeButton(WidgetTester tester, Finder buttonFinder) async {
  expect(buttonFinder, findsOneWidget, reason: 'SwipeButton should be visible');

  final buttonRect = tester.getRect(buttonFinder);
  // Handle is 80px wide, starts at left edge
  const handleWidth = 80.0;
  final handleCenter = Offset(
    buttonRect.left + handleWidth / 2,
    buttonRect.center.dy,
  );
  final dragDistance = buttonRect.width - handleWidth;

  // Use dragFrom with absolute coordinates for more reliable dragging
  await tester.dragFrom(handleCenter, Offset(dragDistance * 0.9, 0));
  // Use pump() instead of pumpAndSettle() due to continuous animations
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _swipeToStartLineup(WidgetTester tester) async {
  // Find the start lineup SwipeButton (labeled "Start Lineup" or similar)
  final buttons = find.byType(SwipeButton);
  print('Found ${buttons.evaluate().length} swipe button(s)');

  // In pre-period state, there should be exactly one SwipeButton (Start Lineup)
  // After end timeout, there might be two (Start Lineup + Undo)
  // We want the first one for start lineup
  final button = buttons.first;
  await _swipeButton(tester, button);
}

Future<void> _swipeUndoButton(WidgetTester tester) async {
  // Find the undo SwipeButton - it should contain "Undo:" in its label
  // This should be the second SwipeButton on screen (after Start Lineup)
  final buttons = find.byType(SwipeButton);
  print('Found ${buttons.evaluate().length} swipe button(s) for undo');

  // Wait for undo action to become available
  await _pumpUntil(
    tester,
    () => _state(tester).hasUndoAction,
  );

  // In connected mode with undo available, we should have 2 buttons
  // The undo button should be the last one (or we can find by ancestor)
  expect(buttons, findsAtLeast(1), reason: 'Should have at least one SwipeButton');

  // Get the last SwipeButton which should be the undo
  final buttonList = buttons.evaluate().toList();
  final undoButton = find.byWidget(buttonList.last.widget);

  await _swipeButton(tester, undoButton);
}

Future<void> _tapJamControl(
  WidgetTester tester,
  String label,
) async {
  // JamControls shows a confirmation state ("JAM STARTED"/"JAM ENDED") for
  // cooldownDuration after each jam transition. The confirmation is based on
  // DateTime.now() (real time); tester.pump(duration) advances real time on
  // device, so pumping past it ensures the button is back to its normal label.
  await tester.pump(JamControls.cooldownDuration + const Duration(milliseconds: 200));

  final target = find.text(label.toUpperCase());
  await _pumpUntil(tester, () => target.evaluate().isNotEmpty);
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
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
    await _ensurePrePeriod(tester);

    await _swipeToStartLineup(tester);

    await _pumpUntil(tester, () {
      final state = _state(tester);
      return state.clocks['Lineup']!.running &&
          !state.clocks['Jam']!.running &&
          !state.clocks['Period']!.running;
    }, timeout: const Duration(seconds: 20));
  });

  testWidgets('Starting initial jam starts jam and period clocks',
      (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensurePrePeriod(tester);
    await _swipeToStartLineup(tester);

    await _tapJamControl(tester, _state(tester).labelStart);

    await _pumpUntil(tester, () {
      final state = _state(tester);
      return state.clocks['Jam']!.running && state.clocks['Period']!.running;
    }, timeout: const Duration(seconds: 20));
  });

  testWidgets('Stop jam ends jam and starts lineup', (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensurePrePeriod(tester);
    await _swipeToStartLineup(tester);
    await _tapJamControl(tester, _state(tester).labelStart);

    await _pumpUntil(
      tester,
      () => _state(tester).clocks['Jam']!.running,
      timeout: const Duration(seconds: 20),
    );

    await _tapJamControl(tester, _state(tester).labelStop);

    await _pumpUntil(tester, () {
      final state = _state(tester);
      return !state.clocks['Jam']!.running && state.clocks['Lineup']!.running;
    }, timeout: const Duration(seconds: 20));
  });

  testWidgets('Timeout flow highlights controls and undo restores timeout',
      (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensurePrePeriod(tester);
    await _swipeToStartLineup(tester);
    await _waitForTeamServerIds(tester);

    await _tapJamControl(tester, _state(tester).labelTimeout);
    await _waitForTimeoutMode(tester);
    await _pumpUntil(
      tester,
      () => _state(tester).clocks['Timeout']!.running,
      timeout: const Duration(seconds: 20),
    );

    // Find timeout menu buttons by their InkWell widgets containing the text
    // The new menu uses custom InkWell buttons with uppercase text
    final timeoutButtons = find.widgetWithText(InkWell, 'TIMEOUT');
    final reviewButtons = find.widgetWithText(InkWell, 'REVIEW');
    final officialTimeoutButton = find.widgetWithText(InkWell, 'OFFICIAL TIMEOUT');

    await _pumpUntil(
      tester,
      () => timeoutButtons.evaluate().length >= 2 &&
          reviewButtons.evaluate().length >= 2 &&
          officialTimeoutButton.evaluate().isNotEmpty,
    );

    await tester.tap(timeoutButtons.first);
    await tester.pump();
    await _pumpUntil(tester, () {
      final state = _state(tester);
      return state.timeoutOwner == state.team1.serverId &&
          !_isOfficialReview(state);
    });

    await tester.tap(timeoutButtons.at(1));
    await tester.pump();
    await _pumpUntil(tester, () {
      final state = _state(tester);
      return state.timeoutOwner == state.team2.serverId &&
          !_isOfficialReview(state);
    });

    await tester.tap(officialTimeoutButton);
    await tester.pump();
    await _pumpUntil(
      tester,
      () => _state(tester).timeoutOwner == 'O',
    );

    await tester.tap(reviewButtons.first);
    await tester.pump();
    await _pumpUntil(tester, () {
      final state = _state(tester);
      return state.timeoutOwner == state.team1.serverId &&
          _isOfficialReview(state);
    });

    await tester.tap(reviewButtons.at(1));
    await tester.pump();
    await _pumpUntil(tester, () {
      final state = _state(tester);
      return state.timeoutOwner == state.team2.serverId &&
          _isOfficialReview(state);
    });

    final endTimeoutButton = find.widgetWithText(InkWell, 'END TIMEOUT');
    await tester.ensureVisible(endTimeoutButton);
    await tester.tap(endTimeoutButton);
    await tester.pump();
    await _pumpUntil(tester, () {
      final state = _state(tester);
      return state.clocks['Lineup']!.running;
    }, timeout: const Duration(seconds: 20));

    // Wait for undo action to be available
    await _pumpUntil(
      tester,
      () => _state(tester).hasUndoAction,
    );

    // Swipe the undo button to restore timeout
    await _swipeUndoButton(tester);

    await _pumpUntil(
      tester,
      () => _state(tester).clocks['Timeout']!.running,
      timeout: const Duration(seconds: 20),
    );
  });

  testWidgets('Pre-game shows GAME and READY instead of lineup clock',
      (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensurePrePeriod(tester);

    // Verify "GAME" and "READY" are displayed
    await _pumpUntil(
      tester,
      () => find.text('GAME').evaluate().isNotEmpty &&
          find.text('READY').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
    );

    expect(find.text('GAME'), findsOneWidget);
    expect(find.text('READY'), findsOneWidget);
  });

  testWidgets('Undo SwipeButton shows No Undo Available when disabled',
      (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensurePrePeriod(tester);

    // Verify we're in pre-game state with no undo available.
    await _pumpUntil(
      tester,
      () => !_state(tester).hasUndoAction,
      timeout: const Duration(seconds: 10),
    );

    // Find the undo SwipeButton - it should show "No Undo Available"
    // In remote mode, there should be 2 SwipeButtons: Start Lineup and Undo
    final buttons = find.byType(SwipeButton);
    await _pumpUntil(
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

  testWidgets('Undo SwipeButton shows action label when available',
      (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensurePrePeriod(tester);
    await _swipeToStartLineup(tester);

    // Wait for lineup to start
    await _pumpUntil(
      tester,
      () => _state(tester).clocks['Lineup']!.running,
      timeout: const Duration(seconds: 20),
    );

    // Start a jam
    await _tapJamControl(tester, _state(tester).labelStart);

    // Wait for jam to start
    await _pumpUntil(
      tester,
      () => _state(tester).clocks['Jam']!.running,
      timeout: const Duration(seconds: 20),
    );

    // Stop the jam
    await _tapJamControl(tester, _state(tester).labelStop);

    // Wait for lineup to start (after jam stop)
    await _pumpUntil(
      tester,
      () => _state(tester).clocks['Lineup']!.running,
      timeout: const Duration(seconds: 20),
    );

    // Wait for undo action to become available.
    await _pumpUntil(
      tester,
      () => _state(tester).hasUndoAction,
      timeout: const Duration(seconds: 10),
    );

    // Verify the undo button shows the action label from state.
    // SwipeButton renders its label in uppercase.
    expect(_state(tester).hasUndoAction, isTrue);
    final undoLabel = _state(tester).labelUndo;
    expect(
      find.textContaining(undoLabel.toUpperCase()),
      findsAtLeast(1),
      reason: 'Undo label "$undoLabel" should be visible on screen',
    );
  });

  testWidgets('Post-intermission shows PERIOD 2 and READY', (tester) async {
    final client = await _launchAppAndConnect(tester);
    addTearDown(client.close);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    await client.startNewGame();
    await _ensurePrePeriod(tester);
    await _swipeToStartLineup(tester);

    // Start the jam to begin period 1
    await _tapJamControl(tester, _state(tester).labelStart);
    await _pumpUntil(
      tester,
      () => _state(tester).clocks['Jam']!.running,
      timeout: const Duration(seconds: 20),
    );

    // Get the game ID and set period clock to almost zero
    final gameId = _state(tester).gameId;
    client.setClockTime(gameId, 'Period', 1000);
    await tester.pump(const Duration(milliseconds: 500));

    // Stop the jam - this should trigger intermission since period is ending
    await _tapJamControl(tester, _state(tester).labelStop);
    await tester.pump(const Duration(seconds: 1));

    // Wait for intermission to start
    await _pumpUntil(
      tester,
      () => _state(tester).clocks['Intermission']!.running,
      timeout: const Duration(seconds: 10),
    );

    // Set intermission clock to almost zero to speed it up
    client.setClockTime(gameId, 'Intermission', 1000);
    await tester.pump(const Duration(milliseconds: 500));

    // Wait for intermission to end and ready state to appear
    await _pumpUntil(
      tester,
      () => !_state(tester).clocks['Intermission']!.running &&
          _state(tester).clocks['Intermission']!.time == 0,
      timeout: const Duration(seconds: 10),
    );

    // Verify "PERIOD 2" and "READY" are displayed
    await _pumpUntil(
      tester,
      () => find.text('PERIOD 2').evaluate().isNotEmpty &&
          find.text('READY').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 10),
    );

    expect(find.text('PERIOD 2'), findsAtLeast(1));
    expect(find.text('READY'), findsOneWidget);
  });
}

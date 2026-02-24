import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:roller_derby_jam_timer/main.dart' as app;
import 'package:roller_derby_jam_timer/models/scoreboard_state.dart';
import 'package:roller_derby_jam_timer/screens/jam_timer_screen.dart';
import 'package:roller_derby_jam_timer/widgets/swipe_button.dart';

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
    () => _state(tester).connectionStatus == 'Connected',
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

bool _isOfficialReview(ScoreboardState state) =>
    state.officialReview == 'true' || state.officialReview == 'True';

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
      return state.clocks['Timeout']!.running ||
          state.labelStop == 'End Timeout';
    },
    timeout: const Duration(seconds: 20),
  );
}

Future<void> _swipeToStartLineup(WidgetTester tester) async {
  final button = find.byType(SwipeButton);
  print('Found swipe button: $button');
  expect(button, findsOneWidget, reason: 'SwipeButton should be visible');

  final buttonRect = tester.getRect(button);
  // Handle is 80px wide, starts at left edge
  const handleWidth = 80.0;
  final handleCenter = Offset(
    buttonRect.left + handleWidth / 2,
    buttonRect.center.dy,
  );
  final dragDistance = buttonRect.width - handleWidth;

  print('Going to drag: $handleCenter to $dragDistance');
  // Use dragFrom with absolute coordinates for more reliable dragging
  await tester.dragFrom(handleCenter, Offset(dragDistance * 0.9, 0));
  // Use pump() instead of pumpAndSettle() due to continuous animations
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tapJamControl(
  WidgetTester tester,
  String label,
) async {
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

    await _pumpUntil(
      tester,
      () => _state(tester).labelUndo != 'No Action',
    );
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await _pumpUntil(
      tester,
      () => find.text(_state(tester).labelUndo.toUpperCase())
          .evaluate()
          .isNotEmpty,
    );
    await tester.tap(find.text(_state(tester).labelUndo.toUpperCase()));
    await tester.pump();
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

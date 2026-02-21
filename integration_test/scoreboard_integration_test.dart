import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:roller_derby_scoreboard_flutter/main.dart' as app;
import 'package:roller_derby_scoreboard_flutter/models/scoreboard_state.dart';
import 'package:roller_derby_scoreboard_flutter/screens/jam_timer_screen.dart';
import 'package:roller_derby_scoreboard_flutter/widgets/swipe_button.dart';

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

  Future<void> close() async {
    await _channel.sink.close();
  }
}

Uri _scoreboardWsUri(String host, int port) {
  final base = Uri.parse('ws://$host:$port');
  return base.replace(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    path: '/WS/',
    queryParameters: const {'source': 'integration', 'platform': 'test'},
  );
}

String _scoreboardHost() {
  const host = String.fromEnvironment('SCOREBOARD_HOST');
  return host.isNotEmpty ? host : 'ryan.local';
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

  SharedPreferences.setMockInitialValues({
    'server_host': host,
    'server_port': port.toString(),
  });

  app.main();
  await tester.pumpAndSettle();

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
  final handle = find.byIcon(Icons.double_arrow_rounded);
  final button = find.byType(SwipeButton);

  final handleRect = tester.getRect(handle);
  final buttonRect = tester.getRect(button);
  final maxDrag = buttonRect.width - handleRect.width;

  await tester.drag(handle, Offset(maxDrag * 0.9, 0));
  await tester.pumpAndSettle();
}

Future<void> _tapJamControl(
  WidgetTester tester,
  String label,
) async {
  final target = find.text(label.toUpperCase());
  await _pumpUntil(tester, () => target.evaluate().isNotEmpty);
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

    final timeoutButtons = find.widgetWithText(OutlinedButton, 'Timeout');
    final reviewButtons = find.widgetWithText(OutlinedButton, 'Review');
    final officialTimeoutButton =
        find.widgetWithText(OutlinedButton, 'Official TO');

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

    await tester.tap(find.widgetWithText(ElevatedButton, 'END TIMEOUT'));
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
}

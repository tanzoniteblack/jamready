/// On-device smoke test for the offline (local) game mode.
///
/// Run on a real device or simulator:
///   flutter test integration_test/offline_game_integration_test.dart
///
/// This is an intentionally minimal smoke test that validates the full WFTDA
/// game flow end-to-end on a real device, with real timing (3-second cooldown).
/// All other offline-game tests live in test/offline_game_widget_test.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:jam_ready/models/game_config.dart';
import 'package:jam_ready/models/ruleset.dart';
import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/screens/jam_timer_screen.dart';
import 'package:jam_ready/services/local_game_engine.dart';

import '../test/helpers/common_helpers.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<(ScoreboardState, LocalGameEngine)> _setupGame(
  WidgetTester tester, {
  Ruleset? ruleset,
  String team1 = 'Home',
  String team2 = 'Away',
}) async {
  final state = ScoreboardState();
  final config = GameConfig(
    ruleset: ruleset ?? Ruleset.wftda(),
    team1Name: team1,
    team2Name: team2,
  );
  final engine = LocalGameEngine(state, config);

  await tester.pumpWidget(
    MultiProvider(
      providers: [ChangeNotifierProvider.value(value: state)],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: JamTimerScreen(engine: engine),
      ),
    ),
  );

  await tester.pumpAndSettle();
  return (state, engine);
}

Future<void> _setClock(
  WidgetTester tester,
  LocalGameEngine engine,
  String clockName,
  int timeMs,
) async {
  engine.setClockTime(clockName, timeMs);
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _runFullGamePeriod(
  WidgetTester tester,
  LocalGameEngine engine,
  ScoreboardState state, {
  bool isFinal = false,
}) async {
  await swipeToStartLineup(tester);
  await validateActiveDisplay(tester, ActiveDisplay.lineup);
  await tapJamControl(tester, state.labelStart);
  await validateActiveDisplay(tester, ActiveDisplay.jam);
  await _setClock(tester, engine, 'Period', 0);
  expect(state.clocks['Jam']!.running, isTrue);
  await validateActiveDisplay(tester, ActiveDisplay.jam);
  await tapJamControl(tester, state.labelStop);
  if (isFinal) {
    await validateActiveDisplay(tester, ActiveDisplay.unofficialScore);
  } else {
    await validateActiveDisplay(tester, ActiveDisplay.intermission);
    await _setClock(tester, engine, 'Intermission', 0);
  }
}

// ---------------------------------------------------------------------------
// Smoke test
// ---------------------------------------------------------------------------

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (ByteData? message) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  testWidgets('full WFTDA game flow', (tester) async {
    final ruleset = Ruleset.wftda();
    final (state, engine) = await _setupGame(tester, ruleset: ruleset);
    addTearDown(engine.dispose);

    await validateActiveDisplay(tester, ActiveDisplay.ready);

    // Period 1
    await _runFullGamePeriod(tester, engine, state);

    // Period 2 (final)
    await _runFullGamePeriod(tester, engine, state, isFinal: true);

    await tapButton(tester, find.text('END GAME'));
    await validateActiveDisplay(tester, ActiveDisplay.gameOver);
  });
}

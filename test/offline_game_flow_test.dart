import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roller_derby_jam_timer/models/scoreboard_state.dart';
import 'package:roller_derby_jam_timer/models/game_config.dart';
import 'package:roller_derby_jam_timer/models/ruleset.dart';
import 'package:roller_derby_jam_timer/screens/settings_screen.dart';
import 'package:roller_derby_jam_timer/screens/game_setup_screen.dart';
import 'package:roller_derby_jam_timer/screens/jam_timer_screen.dart';
import 'package:roller_derby_jam_timer/services/local_game_engine.dart';
import 'package:roller_derby_jam_timer/widgets/swipe_button.dart';
import 'package:roller_derby_jam_timer/widgets/time_edit_dialog.dart';
import 'package:roller_derby_jam_timer/widgets/prominent_period_clock.dart';
import 'package:roller_derby_jam_timer/widgets/clock_display.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Mock wakelock
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (ByteData? message) async {
        return const StandardMessageCodec().encodeMessage(<Object?>[null]);
      },
    );
  });

  group('Offline Game Flow', () {
    testWidgets('settings screen shows offline game option', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScoreboardState()),
          ],
          child: MaterialApp(
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pump();

      // Find the offline game button
      expect(find.text('START OFFLINE GAME'), findsOneWidget);
    });

    testWidgets('game setup screen shows ruleset options', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScoreboardState()),
          ],
          child: MaterialApp(
            home: const GameSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      // Should show ruleset options
      expect(find.text('WFTDA'), findsOneWidget);
      expect(find.text('RDCL'), findsOneWidget);

      // Should show team name inputs
      expect(find.text('Team 1'), findsOneWidget);
      expect(find.text('Team 2'), findsOneWidget);

      // Should show start button
      expect(find.text('START GAME'), findsOneWidget);
    });

    testWidgets('can select RDCL ruleset', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScoreboardState()),
          ],
          child: MaterialApp(
            home: const GameSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      // Tap RDCL
      await tester.tap(find.text('RDCL'));
      await tester.pump();

      // RDCL details should show 4×15min periods and 60s jams
      expect(find.text('4×15min'), findsOneWidget); // periods summary
      expect(find.text('60s'), findsOneWidget); // jam duration
    });

    testWidgets('default WFTDA ruleset shows correct details', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScoreboardState()),
          ],
          child: MaterialApp(
            home: const GameSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      // WFTDA details should show 2×30min periods and 120s jams
      expect(find.text('2×30min'), findsOneWidget); // periods summary
      expect(find.text('120s'), findsOneWidget); // jam duration
    });

    testWidgets('can enter custom team names', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScoreboardState()),
          ],
          child: MaterialApp(
            home: const GameSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      // Find team 1 text field and enter custom name
      final team1Field = find.byType(TextFormField).first;
      await tester.enterText(team1Field, 'Thunder');
      await tester.pump();

      // The text should be in the field
      expect(find.text('Thunder'), findsOneWidget);
    });

    testWidgets('start game navigates to jam timer', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScoreboardState()),
          ],
          child: MaterialApp(
            home: const GameSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      // Tap start game
      await tester.tap(find.text('START GAME'));
      await tester.pumpAndSettle();

      // Should now show jam timer screen
      expect(find.text('ROLLER DERBY JAM TIMER'), findsOneWidget);
    });

    testWidgets('offline game shows team names from setup', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScoreboardState()),
          ],
          child: MaterialApp(
            home: const GameSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      // Start game with default names (Salt/Pepper)
      await tester.tap(find.text('START GAME'));
      await tester.pumpAndSettle();

      // Should show default team names
      expect(find.text('Salt'), findsOneWidget);
      expect(find.text('Pepper'), findsOneWidget);
    });

    testWidgets('offline game does not show undo controls', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScoreboardState()),
          ],
          child: MaterialApp(
            home: const GameSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('START GAME'));
      await tester.pumpAndSettle();

      // Undo controls should NOT be shown in offline mode
      expect(find.text('UNDO CONTROLS'), findsNothing);
    });

    testWidgets('offline game shows swipe to start in pre-game', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScoreboardState()),
          ],
          child: MaterialApp(
            home: const GameSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('START GAME'));
      await tester.pumpAndSettle();

      // Should show at least one swipe button in pre-game state
      expect(find.byType(SwipeButton), findsAtLeastNWidgets(1));
      // Text is uppercased in the widget
      expect(find.text('SLIDE TO START LINEUP'), findsOneWidget);
    });

    testWidgets('offline game shows READY display', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ScoreboardState()),
          ],
          child: MaterialApp(
            home: const GameSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('START GAME'));
      await tester.pumpAndSettle();

      // Should show READY indicator
      expect(find.text('READY'), findsOneWidget);
      expect(find.text('GAME'), findsOneWidget); // "GAME READY" before period 1
    });

    testWidgets('offline game status shows Offline Game', (tester) async {
      SharedPreferences.setMockInitialValues({});

      final state = ScoreboardState();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => state),
          ],
          child: MaterialApp(
            home: const GameSetupScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('START GAME'));
      await tester.pumpAndSettle();

      // Check that the state shows offline game status
      expect(state.connectionStatus, 'Offline Game');
    });

    testWidgets('long press on clock opens time edit dialog', (tester) async {
      SharedPreferences.setMockInitialValues({});

      final state = ScoreboardState();
      final config = GameConfig(
        ruleset: Ruleset.wftda(),
        team1Name: 'Home',
        team2Name: 'Away',
      );
      final engine = LocalGameEngine(state, config);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
          ],
          child: MaterialApp(
            home: JamTimerScreen(engine: engine),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the prominent period clock and long press on the time display
      final periodClock = find.byType(ProminentPeriodClock);
      expect(periodClock, findsOneWidget);

      // Long press on the clock time area
      await tester.longPress(periodClock);
      await tester.pumpAndSettle();

      // Time edit dialog should appear
      expect(find.byType(TimeEditDialog), findsOneWidget);
      expect(find.text('CANCEL'), findsOneWidget);
      expect(find.text('SET TIME'), findsOneWidget);

      // Clean up
      await engine.dispose();
    });

    testWidgets('period time adjustment before game start is preserved',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      final state = ScoreboardState();
      final config = GameConfig(
        ruleset: Ruleset.wftda(),
        team1Name: 'Home',
        team2Name: 'Away',
      );
      final engine = LocalGameEngine(state, config);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
          ],
          child: MaterialApp(
            home: JamTimerScreen(engine: engine),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial period time should be 30:00 (1800000ms) for WFTDA
      expect(state.clocks['Period']!.time, 30 * 60 * 1000);

      // Adjust the period clock down by 5 minutes (300 seconds = 300000ms)
      engine.adjustClock('Period', -5 * 60 * 1000);
      await tester.pump();

      // Period time should now be 25:00
      expect(state.clocks['Period']!.time, 25 * 60 * 1000);

      // Start lineup (slide to start)
      engine.stopJam(); // This triggers _startPeriod(1) + _startLineup()
      await tester.pump();

      // Period time should still be 25:00 (preserved, not reset to 30:00)
      expect(state.clocks['Period']!.time, 25 * 60 * 1000);
      expect(state.clocks['Period']!.number, 1);

      // Clean up
      await engine.dispose();
    });

    testWidgets('period time resets after intermission for next period',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      final state = ScoreboardState();
      // Use a short period for testing
      final shortRuleset = Ruleset.wftda().copyWith(
        periodDurationMs: 5000, // 5 seconds
        jamDurationMs: 2000, // 2 seconds
      );
      final config = GameConfig(
        ruleset: shortRuleset,
        team1Name: 'Home',
        team2Name: 'Away',
      );
      final engine = LocalGameEngine(state, config);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
          ],
          child: MaterialApp(
            home: JamTimerScreen(engine: engine),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start the game
      engine.stopJam(); // Start lineup
      await tester.pump();
      expect(state.clocks['Period']!.number, 1);

      // Manually set period clock to 0 to simulate end of period
      engine.setClockTime('Period', 0);
      await tester.pump();

      // Start and end a jam to trigger period end
      engine.startJam();
      await tester.pump();
      engine.stopJam(); // This should trigger _endPeriod -> intermission
      await tester.pump();

      // Should be in intermission
      expect(state.clocks['Intermission']!.running, true);

      // End intermission to start period 2
      engine.startJam(); // This ends intermission and starts period 2
      await tester.pump();

      // Period 2 should have full time (reset to ruleset duration)
      expect(state.clocks['Period']!.number, 2);
      expect(state.clocks['Period']!.time, 5000); // Reset to 5 seconds

      // Clean up
      await engine.dispose();
    });

    testWidgets('spam detection shows long-press hint after rapid button presses',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      // Use a tall viewport so the hint text doesn't cause a layout overflow
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final state = ScoreboardState();
      final config = GameConfig(
        ruleset: Ruleset.wftda(),
        team1Name: 'Home',
        team2Name: 'Away',
      );
      final engine = LocalGameEngine(state, config);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
          ],
          child: MaterialApp(
            home: JamTimerScreen(engine: engine),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find the +1 button on the period clock
      final plusButton = find.text('+1').first;
      expect(plusButton, findsOneWidget);

      // Initially no hint should be shown
      expect(find.textContaining('Long-press'), findsNothing);

      // Rapidly tap the +1 button 6 times
      for (int i = 0; i < 6; i++) {
        await tester.tap(plusButton);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump();

      // Hint should now be visible
      expect(find.textContaining('Long-press'), findsOneWidget);
      expect(find.textContaining('jump to any value'), findsOneWidget);

      // Wait for the auto-hide timer to complete (4 seconds)
      await tester.pump(const Duration(seconds: 5));

      // Hint should now be hidden
      expect(find.textContaining('Long-press'), findsNothing);

      // Clean up
      await engine.dispose();
    });

    testWidgets('time edit dialog shows wheel pickers', (tester) async {
      SharedPreferences.setMockInitialValues({});

      final state = ScoreboardState();
      final config = GameConfig(
        ruleset: Ruleset.wftda(),
        team1Name: 'Home',
        team2Name: 'Away',
      );
      final engine = LocalGameEngine(state, config);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
          ],
          child: MaterialApp(
            home: JamTimerScreen(engine: engine),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Long press to open dialog
      final periodClock = find.byType(ProminentPeriodClock);
      await tester.longPress(periodClock);
      await tester.pumpAndSettle();

      // Dialog should have two CupertinoPicker widgets (minutes and seconds)
      expect(find.byType(CupertinoPicker), findsNWidgets(2));

      // Should show the colon separator
      expect(find.text(':'), findsOneWidget);

      // Clean up - dismiss dialog
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      await engine.dispose();
    });
  });
}

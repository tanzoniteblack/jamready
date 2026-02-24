import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:roller_derby_jam_timer/models/scoreboard_state.dart';
import 'package:roller_derby_jam_timer/screens/settings_screen.dart';
import 'package:roller_derby_jam_timer/screens/game_setup_screen.dart';
import 'package:roller_derby_jam_timer/widgets/swipe_button.dart';

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
      expect(find.text('JAM TIMER'), findsOneWidget);
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

      // Should show swipe button in pre-game state
      expect(find.byType(SwipeButton), findsOneWidget);
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
  });
}

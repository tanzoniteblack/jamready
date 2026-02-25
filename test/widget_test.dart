import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/screens/home_screen.dart';
import 'package:jam_ready/screens/jam_timer_screen.dart';

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

  testWidgets('Home screen smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    // Build the app with home screen and required providers
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ScoreboardState()),
        ],
        child: MaterialApp(
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pump();

    // Verify home screen elements are present
    expect(find.text('Game Hub'), findsOneWidget);
    expect(find.text('REMOTE SCOREBOARD'), findsOneWidget);
    expect(find.text('SCAN SCOREBOARD QR'), findsOneWidget);
    expect(find.text('START REMOTE SESSION'), findsOneWidget);

    // Verify text fields are present
    expect(find.widgetWithText(TextFormField, 'Host / IP Address'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Port'), findsOneWidget);
  });

  testWidgets('Jam timer screen smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    // Build the app with jam timer screen and required providers
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ScoreboardState()),
        ],
        child: MaterialApp(
          home: const JamTimerScreen(),
        ),
      ),
    );
    await tester.pump();

    // Verify jam timer screen elements are present
    expect(find.text('JamReady'), findsOneWidget);

    // Verify home/config button is present
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
  });
}

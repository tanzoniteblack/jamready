import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:roller_derby_jam_timer/main.dart';
import 'package:roller_derby_jam_timer/models/scoreboard_state.dart';

void main() {
  testWidgets('Settings screen smoke test', (WidgetTester tester) async {
    // Build the app with settings screen and required providers
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ScoreboardState()),
        ],
        child: const MyApp(showSettings: true),
      ),
    );

    // Verify settings screen elements are present
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('SERVER CONFIGURATION'), findsOneWidget);
    expect(find.text('SCAN QR CODE'), findsOneWidget);
    expect(find.text('CONNECT'), findsOneWidget);

    // Verify text fields are present
    expect(find.widgetWithText(TextFormField, 'Host / IP Address'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Port'), findsOneWidget);
  });

  testWidgets('Jam timer screen smoke test', (WidgetTester tester) async {
    // Build the app with jam timer screen and required providers
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ScoreboardState()),
        ],
        child: const MyApp(showSettings: false),
      ),
    );

    // Verify jam timer screen elements are present
    expect(find.text('JAM TIMER'), findsOneWidget);

    // Verify settings button is present
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
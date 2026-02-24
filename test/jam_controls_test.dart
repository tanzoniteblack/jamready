import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roller_derby_jam_timer/widgets/jam_controls.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [widget] in a minimal MaterialApp+Scaffold for widget testing.
Widget _wrap(Widget widget) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: Center(child: widget)),
  );
}

/// Builds a JamControls with sensible defaults; override only what matters.
Widget _buildControls({
  bool inJam = false,
  bool isPrePeriod = false,
  bool isIntermission = false,
  bool enabled = true,
  String startLabel = 'Start Jam',
  String stopLabel = 'Stop Jam',
  String timeoutLabel = 'Timeout',
  VoidCallback? onStartJam,
  VoidCallback? onStopJam,
  VoidCallback? onTimeout,
}) {
  return _wrap(
    JamControls(
      inJam: inJam,
      isPrePeriod: isPrePeriod,
      isIntermission: isIntermission,
      startLabel: startLabel,
      stopLabel: stopLabel,
      timeoutLabel: timeoutLabel,
      enabled: enabled,
      onStartJam: onStartJam ?? () {},
      onStopJam: onStopJam ?? () {},
      onTimeout: onTimeout ?? () {},
    ),
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // Label display
  // ---------------------------------------------------------------------------

  group('label display', () {
    testWidgets('shows uppercase start label when not in jam', (tester) async {
      await tester.pumpWidget(_buildControls(startLabel: 'Start Jam'));

      expect(find.text('START JAM'), findsOneWidget);
    });

    testWidgets('shows uppercase stop label when in jam', (tester) async {
      await tester.pumpWidget(
          _buildControls(inJam: true, stopLabel: 'Stop Jam'));

      expect(find.text('STOP JAM'), findsOneWidget);
    });

    testWidgets('shows swipe widget text when isPrePeriod', (tester) async {
      await tester.pumpWidget(_buildControls(isPrePeriod: true));

      // SwipeButton calls toUpperCase() on its label
      expect(find.text('SLIDE TO START LINEUP'), findsOneWidget);
    });

    testWidgets('shows uppercase timeout label', (tester) async {
      await tester.pumpWidget(_buildControls(timeoutLabel: 'Timeout'));

      expect(find.text('TIMEOUT'), findsOneWidget);
    });

    testWidgets('stop label takes priority over start label when inJam', (tester) async {
      await tester.pumpWidget(
          _buildControls(inJam: true, startLabel: 'Start Jam', stopLabel: 'Stop Jam'));

      expect(find.text('STOP JAM'), findsOneWidget);
      expect(find.text('START JAM'), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  group('callbacks', () {
    testWidgets('tapping start button fires onStartJam', (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
          _buildControls(onStartJam: () => callCount++));

      await tester.tap(find.text('START JAM'));
      // Pump past cooldown so the scheduled Future.delayed completes
      await tester.pump(JamControls.cooldownDuration + const Duration(milliseconds: 1));

      expect(callCount, 1);
    });

    testWidgets('tapping stop button fires onStopJam when in jam', (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
          _buildControls(inJam: true, onStopJam: () => callCount++));

      await tester.tap(find.text('STOP JAM'));
      await tester.pump(JamControls.cooldownDuration + const Duration(milliseconds: 1));

      expect(callCount, 1);
    });

    testWidgets('tapping timeout button fires onTimeout', (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
          _buildControls(onTimeout: () => callCount++));

      await tester.tap(find.text('TIMEOUT'));
      await tester.pump();

      expect(callCount, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Cooldown
  // ---------------------------------------------------------------------------

  group('cooldown', () {
    testWidgets('second tap immediately after first is ignored (cooldown active)',
        (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
          _buildControls(onStartJam: () => callCount++));

      // First tap – should fire
      await tester.tap(find.text('START JAM'));
      await tester.pump();

      // Second tap immediately – cooldown prevents it
      await tester.tap(find.text('START JAM'));
      await tester.pump();

      expect(callCount, 1);

      // Pump past cooldown to let Future.delayed settle
      await tester.pump(JamControls.cooldownDuration + const Duration(milliseconds: 1));
    });

    // Note: testing cooldown expiry requires real wall-clock time (the widget
    // uses DateTime.now(), not the fake async clock), so that scenario is
    // covered by the integration tests instead.
  });

  // ---------------------------------------------------------------------------
  // Disabled state
  // ---------------------------------------------------------------------------

  group('disabled state', () {
    testWidgets('tapping start button when disabled does not fire onStartJam',
        (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
          _buildControls(enabled: false, onStartJam: () => callCount++));

      await tester.tap(find.text('START JAM'), warnIfMissed: false);
      await tester.pump();

      expect(callCount, 0);
    });

    testWidgets('timeout button is disabled during intermission', (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
          _buildControls(isIntermission: true, onTimeout: () => callCount++));

      await tester.tap(find.text('TIMEOUT'), warnIfMissed: false);
      await tester.pump();

      expect(callCount, 0);
    });
  });
}

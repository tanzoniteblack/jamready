import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jam_ready/widgets/jam_controls.dart';

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
  int jamClockNumber = 0,
  int lineupClockNumber = 0,
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
      jamClockNumber: jamClockNumber,
      lineupClockNumber: lineupClockNumber,
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
  // Confirmation state
  // ---------------------------------------------------------------------------

  group('confirmation state', () {
    testWidgets('shows JAM STARTED after tapping start button', (tester) async {
      await tester.pumpWidget(_buildControls());

      await tester.tap(find.text('START JAM'));
      await tester.pump();

      expect(find.text('JAM STARTED'), findsOneWidget);
      expect(find.text('START JAM'), findsNothing);

      // Settle the Future.delayed
      await tester.pump(JamControls.cooldownDuration + const Duration(milliseconds: 1));
    });

    testWidgets('shows JAM ENDED after tapping stop button', (tester) async {
      await tester.pumpWidget(_buildControls(inJam: true));

      await tester.tap(find.text('STOP JAM'));
      await tester.pump();

      expect(find.text('JAM ENDED'), findsOneWidget);
      expect(find.text('STOP JAM'), findsNothing);

      await tester.pump(JamControls.cooldownDuration + const Duration(milliseconds: 1));
    });

    testWidgets('shows JAM STARTED when inJam changes and jam number increments',
        (tester) async {
      // Real server-initiated jam start: Jam.Number goes N → N+1
      await tester.pumpWidget(_buildControls(
          inJam: false, enabled: true, jamClockNumber: 6));
      await tester.pumpWidget(_buildControls(
          inJam: true, enabled: true, jamClockNumber: 7));
      await tester.pump();

      expect(find.text('JAM STARTED'), findsOneWidget);

      await tester.pump(JamControls.cooldownDuration + const Duration(milliseconds: 1));
    });

    testWidgets('shows JAM ENDED when inJam changes and lineup number increments',
        (tester) async {
      // Real server-initiated jam stop: Lineup.Number goes N → N+1
      await tester.pumpWidget(_buildControls(
          inJam: true, enabled: true, lineupClockNumber: 7));
      await tester.pumpWidget(_buildControls(
          inJam: false, enabled: true, lineupClockNumber: 8));
      await tester.pump();

      expect(find.text('JAM ENDED'), findsOneWidget);

      await tester.pump(JamControls.cooldownDuration + const Duration(milliseconds: 1));
    });

    testWidgets('does not show JAM STARTED on initial data load (number jumps)',
        (tester) async {
      // Initial connect: numbers jump from default 0 to whatever the server has
      await tester.pumpWidget(_buildControls(
          inJam: false, enabled: true, jamClockNumber: 0));
      await tester.pumpWidget(_buildControls(
          inJam: true, enabled: true, jamClockNumber: 7));
      await tester.pump();

      expect(find.text('JAM STARTED'), findsNothing);
      expect(find.text('STOP JAM'), findsOneWidget);
    });

    testWidgets('does not show JAM STARTED when inJam changes simultaneously with enabled',
        (tester) async {
      // Initial connect: enabled goes false→true in same update as inJam changes
      await tester.pumpWidget(_buildControls(
          inJam: false, enabled: false, jamClockNumber: 0));
      await tester.pumpWidget(_buildControls(
          inJam: true, enabled: true, jamClockNumber: 1));
      await tester.pump();

      expect(find.text('JAM STARTED'), findsNothing);
      expect(find.text('STOP JAM'), findsOneWidget);
    });

    testWidgets('does not show JAM STARTED on undo-stop-jam (lineup number decrements)',
        (tester) async {
      // Undo restores jam: Lineup.Number goes back down, inJam goes true
      await tester.pumpWidget(_buildControls(
          inJam: false, enabled: true, lineupClockNumber: 8));
      await tester.pumpWidget(_buildControls(
          inJam: true, enabled: true, lineupClockNumber: 7));
      await tester.pump();

      expect(find.text('JAM STARTED'), findsNothing);
      expect(find.text('STOP JAM'), findsOneWidget);
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
      // Pump past confirmation so the scheduled Future.delayed completes
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
  // Cooldown / confirmation guard
  // ---------------------------------------------------------------------------

  group('cooldown', () {
    testWidgets('second tap during confirmation state is ignored',
        (tester) async {
      var callCount = 0;
      await tester.pumpWidget(
          _buildControls(onStartJam: () => callCount++));

      // First tap – fires callback, enters confirmation state showing 'JAM STARTED'
      await tester.tap(find.text('START JAM'));
      await tester.pump();

      expect(find.text('JAM STARTED'), findsOneWidget);

      // Second tap during confirmation – button is not tappable
      await tester.tap(find.text('JAM STARTED'));
      await tester.pump();

      expect(callCount, 1);

      // Pump past confirmation to let Future.delayed settle
      await tester.pump(JamControls.cooldownDuration + const Duration(milliseconds: 1));
    });

    // Note: testing confirmation expiry requires real wall-clock time (the widget
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
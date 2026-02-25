import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jam_ready/models/scoreboard_state.dart';
import 'package:jam_ready/widgets/team_panel.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _wrap(Widget widget) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: Center(child: widget)),
  );
}

Team _makeTeam({
  String id = 'team1',
  String name = 'Home Team',
  String alternateName = '',
  int timeouts = 3,
  int officialReviews = 1,
  bool retainedOfficialReview = false,
}) {
  return Team(
    id: id,
    name: name,
    alternateName: alternateName,
    timeouts: timeouts,
    officialReviews: officialReviews,
    retainedOfficialReview: retainedOfficialReview,
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // Team name display
  // ---------------------------------------------------------------------------

  group('team name display', () {
    testWidgets('shows team name when no alternate name is set', (tester) async {
      final team = _makeTeam(name: 'Roller Rebels');
      await tester.pumpWidget(_wrap(TeamPanel(team: team)));

      expect(find.text('Roller Rebels'), findsOneWidget);
    });

    testWidgets('shows alternate name when it is set', (tester) async {
      final team = _makeTeam(name: 'Roller Rebels', alternateName: 'Rebels');
      await tester.pumpWidget(_wrap(TeamPanel(team: team)));

      expect(find.text('Rebels'), findsOneWidget);
      expect(find.text('Roller Rebels'), findsNothing);
    });

    testWidgets('falls back to name when alternate name is empty', (tester) async {
      final team = _makeTeam(name: 'Doom Squad', alternateName: '');
      await tester.pumpWidget(_wrap(TeamPanel(team: team)));

      expect(find.text('Doom Squad'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Timeouts and official reviews
  // ---------------------------------------------------------------------------

  group('stats display', () {
    testWidgets('shows current timeout count next to TO label', (tester) async {
      final team = _makeTeam(timeouts: 2);
      await tester.pumpWidget(_wrap(TeamPanel(team: team)));

      // "2" and "TO" appear as separate Text widgets
      expect(find.text('2'), findsWidgets); // could match multiple
      expect(find.text('TO'), findsOneWidget);
    });

    testWidgets('shows current official review count next to OR label', (tester) async {
      final team = _makeTeam(officialReviews: 1);
      await tester.pumpWidget(_wrap(TeamPanel(team: team)));

      expect(find.text('OR'), findsOneWidget);
    });

    testWidgets('shows zero timeouts when team has none left', (tester) async {
      final team = _makeTeam(timeouts: 0);
      await tester.pumpWidget(_wrap(TeamPanel(team: team)));

      expect(find.text('TO'), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // Retained official review toggle
  // ---------------------------------------------------------------------------

  group('retained review toggle', () {
    testWidgets('retained toggle is not shown when onRetainedToggle is null', (tester) async {
      final team = _makeTeam();
      await tester.pumpWidget(_wrap(TeamPanel(team: team)));

      expect(find.text('RET'), findsNothing);
    });

    testWidgets('retained toggle is shown when onRetainedToggle is provided', (tester) async {
      final team = _makeTeam();
      await tester.pumpWidget(_wrap(
        TeamPanel(team: team, onRetainedToggle: (_) {}),
      ));

      expect(find.text('RET'), findsOneWidget);
    });

    testWidgets('tapping retained toggle calls onRetainedToggle with toggled value', (tester) async {
      bool? receivedValue;
      final team = _makeTeam(retainedOfficialReview: false);

      await tester.pumpWidget(_wrap(
        TeamPanel(team: team, onRetainedToggle: (val) => receivedValue = val),
      ));

      await tester.tap(find.text('RET'));
      await tester.pump();

      // Called with true (toggled from false)
      expect(receivedValue, true);
    });

    testWidgets('tapping retained toggle when already retained calls with false', (tester) async {
      bool? receivedValue;
      final team = _makeTeam(retainedOfficialReview: true);

      await tester.pumpWidget(_wrap(
        TeamPanel(team: team, onRetainedToggle: (val) => receivedValue = val),
      ));

      await tester.tap(find.text('RET'));
      await tester.pump();

      expect(receivedValue, false);
    });

    testWidgets('retained toggle does nothing when disabled', (tester) async {
      bool called = false;
      final team = _makeTeam();

      await tester.pumpWidget(_wrap(
        TeamPanel(
          team: team,
          enabled: false,
          onRetainedToggle: (_) => called = true,
        ),
      ));

      await tester.tap(find.text('RET'), warnIfMissed: false);
      await tester.pump();

      expect(called, false);
    });
  });
}

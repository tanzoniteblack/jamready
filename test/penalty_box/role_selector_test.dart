import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jam_ready/models/skater_seat.dart';
import 'package:jam_ready/screens/home/role_selector.dart';

void main() {
  Future<List<AppRole>> pumpSelector(WidgetTester tester) async {
    final picked = <AppRole>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoleSelector(
              team1Name: 'Salt',
              team2Name: 'Pepper',
              team1Color: Colors.white,
              team2Color: Colors.black,
              onTap: picked.add,
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  Finder teamButton(String choiceLabel, String teamName) => find.descendant(
    of: find
        .ancestor(of: find.text(choiceLabel), matching: find.byType(Material))
        .first,
    matching: find.widgetWithText(OutlinedButton, teamName),
  );

  testWidgets('features PBT and PBM above the other views', (tester) async {
    await pumpSelector(tester);

    final labels = [
      'Blockers only',
      'Jammers only',
      'OTHER VIEWS',
      'Full team',
      'All players',
    ];
    final tops = labels.map((l) => tester.getTopLeft(find.text(l)).dy).toList();
    expect(tops, [...tops]..sort());

    double rowOf(String text) => tester.getCenter(find.text(text)).dy;
    expect(rowOf('PBT'), closeTo(rowOf('Blockers only'), 2));
    expect(rowOf('PBM'), closeTo(rowOf('Jammers only'), 2));
  });

  testWidgets('fits long team names on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: RoleSelector(
              team1Name: 'Rose City Rollers All-Stars',
              team2Name: 'Gotham Girls Roller Derby',
              team1Color: Colors.white,
              team2Color: Colors.black,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a single tap on a team opens that team view', (tester) async {
    final picked = await pumpSelector(tester);

    final cases = {
      ('Blockers only', 'Salt'): AppRole.team1BlockersOnly,
      ('Blockers only', 'Pepper'): AppRole.team2BlockersOnly,
      ('Full team', 'Salt'): AppRole.team1Full,
      ('Full team', 'Pepper'): AppRole.team2Full,
    };
    for (final MapEntry(key: (choice, team), value: role) in cases.entries) {
      picked.clear();
      await tester.tap(teamButton(choice, team));
      expect(picked, [role], reason: '$choice / $team');
    }
  });

  testWidgets('a single tap on a both-teams view opens it', (tester) async {
    final picked = await pumpSelector(tester);

    await tester.tap(find.text('Jammers only'));
    await tester.tap(find.text('All players'));

    expect(picked, [AppRole.pbm, AppRole.solo]);
  });

  testWidgets('tapping a team tile outside its buttons does nothing', (
    tester,
  ) async {
    final picked = await pumpSelector(tester);

    await tester.tap(find.text('Blockers only'));

    expect(picked, isEmpty);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jam_ready/widgets/skater_entry_dialog.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  List<String> knownNumbers = const ['21', '1', '43'],
  Set<String> onTrackNumbers = const {},
  Listenable? lineupChanges,
  Set<String> Function()? readOnTrack,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSkaterEntryDialog(
            context,
            knownNumbers: knownNumbers,
            onTrackNumbers: readOnTrack ?? () => onTrackNumbers,
            lineupChanges: lineupChanges,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Color? _chipBorder(WidgetTester tester, String number) {
  final container = tester.widget<AnimatedContainer>(
    find.ancestor(
      of: find.text('#$number'),
      matching: find.byType(AnimatedContainer),
    ),
  );
  return ((container.decoration as BoxDecoration).border as Border).top.color;
}

void main() {
  testWidgets('on-track skaters keep the highlight, others are dimmed', (
    tester,
  ) async {
    await _openDialog(tester, onTrackNumbers: {'21'});

    expect(_chipBorder(tester, '21'), Colors.blue.shade700);
    expect(_chipBorder(tester, '1'), Colors.white24);
    expect(_chipBorder(tester, '43'), Colors.white24);
  });

  testWidgets('numbers stay in derby order regardless of who is on track', (
    tester,
  ) async {
    await _openDialog(tester, onTrackNumbers: {'43'});

    final xs = [
      '1',
      '21',
      '43',
    ].map((n) => tester.getTopLeft(find.text('#$n')).dx).toList();
    expect(xs, orderedEquals([...xs]..sort()));
  });

  testWidgets('every skater is dimmed without lineup tracking', (tester) async {
    await _openDialog(tester);

    for (final n in ['1', '21', '43']) {
      expect(_chipBorder(tester, n), Colors.white24);
    }
  });

  testWidgets('keyboard chip switches to typing, grid icon switches back', (
    tester,
  ) async {
    await _openDialog(tester);
    expect(find.byIcon(Icons.grid_view_rounded), findsNothing);

    await tester.tap(find.byIcon(Icons.keyboard));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.keyboard), findsNothing);

    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('#21'), findsOneWidget);
  });

  testWidgets('chips follow lineup updates while the picker is open', (
    tester,
  ) async {
    final onTrack = ValueNotifier<Set<String>>({'21'});
    await _openDialog(
      tester,
      lineupChanges: onTrack,
      readOnTrack: () => onTrack.value,
    );
    expect(_chipBorder(tester, '21'), Colors.blue.shade700);
    expect(_chipBorder(tester, '43'), Colors.white24);

    onTrack.value = {'43'};
    await tester.pumpAndSettle();

    expect(_chipBorder(tester, '21'), Colors.white24);
    expect(_chipBorder(tester, '43'), Colors.blue.shade700);
  });
}

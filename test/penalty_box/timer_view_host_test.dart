import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:jam_ready/models/skater_seat.dart';
import 'package:jam_ready/screens/box_timer/timer_view_host.dart';
import 'package:jam_ready/services/local_penalty_engine.dart';
import 'package:jam_ready/widgets/seat_card.dart';

import 'test_helpers.dart';

void main() {
  final requestedOrientations = <List<String>>[];

  setUp(() {
    requestedOrientations.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            requestedOrientations.add(
              List<String>.from(call.arguments as List),
            );
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('only the jammers-only view permits landscape', (tester) async {
    final state = makeState();
    final engine = LocalPenaltyEngine(state);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(home: TimerViewHost(engine: engine)),
      ),
    );
    await tester.pump();

    expect(
      requestedOrientations.last,
      DeviceOrientation.values.map((value) => value.toString()).toList(),
    );

    state.setTimerView(AppRole.solo);
    await tester.pump();

    expect(requestedOrientations.last, [
      DeviceOrientation.portraitUp.toString(),
      DeviceOrientation.portraitDown.toString(),
    ]);
  });

  testWidgets('timer view menu scrolls in landscape', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = makeState();
    final engine = LocalPenaltyEngine(state);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(home: TimerViewHost(engine: engine)),
      ),
    );

    await tester.tap(find.text('Jammers only'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final menuScrollView = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(SingleChildScrollView),
    );
    expect(menuScrollView, findsOneWidget);

    await tester.ensureVisible(find.text('All players'));
    expect(find.text('All players'), findsOneWidget);
  });

  testWidgets('timers stay present while swapping between every timer view', (
    tester,
  ) async {
    final state = makeState();
    final engine = LocalPenaltyEngine(state);
    state.jamRunning = true;
    state.seatSkater(
      seat: state.team1Jammer,
      number: '10',
      position: SkaterPosition.jammer,
    );
    state.team1Jammer.timeRemaining = const Duration(seconds: 19);
    state.seatSkater(
      seat: state.team2Blocker1,
      number: '20',
      position: SkaterPosition.blocker,
    );
    state.team2Blocker1.timeRemaining = const Duration(seconds: 24);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(home: TimerViewHost(engine: engine)),
      ),
    );

    for (final role in AppRole.values) {
      state.setTimerView(role);
      await tester.pump();

      expect(find.byType(SeatCard), findsWidgets);
      expect(state.team1Jammer.skaterNumber, '10');
      expect(state.team1Jammer.timeRemaining, const Duration(seconds: 19));
      expect(state.team2Blocker1.skaterNumber, '20');
      expect(state.team2Blocker1.timeRemaining, const Duration(seconds: 24));
    }
  });
}

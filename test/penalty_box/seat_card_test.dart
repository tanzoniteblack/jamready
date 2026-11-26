import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:jam_ready/models/penalty_box_state.dart';
import 'package:jam_ready/models/skater_seat.dart';
import 'package:jam_ready/screens/box_timer/timer_view_host.dart';
import 'package:jam_ready/services/local_penalty_engine.dart';
import 'package:jam_ready/widgets/seat_card.dart';

import 'test_helpers.dart';

Widget _jammerCard(PenaltyBoxState state, int teamIdx) =>
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: SeatCard(seat: state.jammerSeat(teamIdx)),
          ),
        ),
      ),
    );

// T1 sits 10 seconds, then T2 arrives: T1 released, T2 owes 10 seconds.
PenaltyBoxState _swappedState() {
  final state = makeState()..onJamStart();
  seatJammer(state, 1, '10');
  state.tick(const Duration(seconds: 10));
  seatJammer(state, 2, '20');
  return state;
}

// After a swap, T1 is released and returns while T2 is still serving.
PenaltyBoxState _bothSittingState() {
  final state = _swappedState();
  state.clearSeat(state.team1Jammer);
  seatJammer(state, 1, '11');
  return state;
}

void main() {
  testWidgets('+30 and −30 controls change the seat timer by 30 seconds', (
    tester,
  ) async {
    final state = makeState();
    final seat = state.team1Blocker1;
    state.seatSkater(
      seat: seat,
      number: '22',
      position: SkaterPosition.blocker,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer<PenaltyBoxState>(
              builder: (_, currentState, _) => SizedBox.expand(
                child: SeatCard(seat: currentState.team1Blocker1),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('+30'));
    await tester.pump();
    expect(seat.timeRemaining, const Duration(seconds: 60));

    await tester.tap(find.text('−30'));
    await tester.pump();
    expect(seat.timeRemaining, const Duration(seconds: 30));
  });

  testWidgets('released jammer card shows how long they sat after a swap', (
    tester,
  ) async {
    final state = _swappedState();
    state.clearSeat(state.team1Jammer);

    await tester.pumpWidget(_jammerCard(state, 1));

    expect(find.text('SAT 0:10'), findsOneWidget);
    expect(find.text('BOTH JAMMERS IN'), findsNothing);
  });

  testWidgets('second jammer card has no swap note', (tester) async {
    await tester.pumpWidget(_jammerCard(_swappedState(), 2));

    expect(find.textContaining('SAT'), findsNothing);
  });

  testWidgets('both jammer cards flag both jammers sitting', (tester) async {
    final state = _bothSittingState();

    await tester.pumpWidget(_jammerCard(state, 1));
    expect(find.text('BOTH JAMMERS IN'), findsOneWidget);

    await tester.pumpWidget(_jammerCard(state, 2));
    expect(find.text('BOTH JAMMERS IN'), findsOneWidget);
    // Swapping seats on the same card fires a stand haptic; let it finish.
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('jammers-only screen shows a banner when both are sitting', (
    tester,
  ) async {
    final state = _bothSittingState();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          home: TimerViewHost(engine: LocalPenaltyEngine(state)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('BOTH JAMMERS IN THE BOX'), findsOneWidget);

    state.tick(const Duration(seconds: 10)); // T2 finishes serving.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('BOTH JAMMERS IN THE BOX'), findsNothing);
  });

  testWidgets(
    'entering a number on an open card presets it without starting a timer',
    (tester) async {
      final state = makeState()..onJamStart();
      final seat = state.team1Blocker1;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 300,
                child: SeatCard(seat: seat),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('#?'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.enterText(find.byType(TextField), '7');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump(const Duration(milliseconds: 500));

      state.tick(const Duration(seconds: 3));
      await tester.pump();

      expect(find.text('#7'), findsOneWidget);
      expect(find.text('OPEN'), findsOneWidget);
      expect(find.text('RELEASE'), findsNothing);
      expect(seat.isEmpty, isTrue);
      expect(seat.overtime, Duration.zero);

      await tester.tap(find.text('OPEN'));
      await tester.pump();

      expect(seat.skaterNumber, '7');
      expect(seat.isRunning, isTrue);
      expect(find.text('SEATED'), findsOneWidget);
    },
  );

  testWidgets('open jammer card shows the scoreboard jammer number', (
    tester,
  ) async {
    final state = makeState();
    await tester.pumpWidget(_jammerCard(state, 1));
    expect(find.text('#?'), findsOneWidget);

    state.updateRoster(1, '17', 'uuid-j1');
    state.updateSkaterRole(1, 'uuid-j1', 'Jammer');
    await tester.pump();

    expect(find.text('#17'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    expect(state.team1Jammer.isRunning, isFalse);
  });
}

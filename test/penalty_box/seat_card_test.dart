import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:jam_ready/models/penalty_box_state.dart';
import 'package:jam_ready/models/skater_seat.dart';
import 'package:jam_ready/widgets/seat_card.dart';

import 'test_helpers.dart';

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
}

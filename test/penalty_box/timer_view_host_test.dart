import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:jam_ready/models/skater_seat.dart';
import 'package:jam_ready/screens/box_timer/timer_view_host.dart';
import 'package:jam_ready/services/local_penalty_engine.dart';
import 'package:jam_ready/widgets/seat_card.dart';

import 'test_helpers.dart';

void main() {
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

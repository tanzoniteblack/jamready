import 'package:flutter_test/flutter_test.dart';
import 'package:jam_ready/models/penalty_box_state.dart';
import 'package:jam_ready/models/skater_seat.dart';
import 'package:jam_ready/screens/box_timer/timer_view_switcher.dart';

void main() {
  group('orderedTimerViews', () {
    test('puts the closest alternatives first for a full-team view', () {
      final state = PenaltyBoxState(role: AppRole.team1Full);

      expect(orderedTimerViews(state), [
        AppRole.team2Full,
        AppRole.team1BlockersOnly,
        AppRole.team2BlockersOnly,
        AppRole.pbm,
        AppRole.solo,
      ]);
    });

    test('keeps specialist views last when starting from all players', () {
      final state = PenaltyBoxState(role: AppRole.solo);

      expect(orderedTimerViews(state), [
        AppRole.team1Full,
        AppRole.team2Full,
        AppRole.team1BlockersOnly,
        AppRole.team2BlockersOnly,
        AppRole.pbm,
        AppRole.solo,
      ]);
    });
  });
}

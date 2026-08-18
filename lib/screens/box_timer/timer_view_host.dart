import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/penalty_box_state.dart';
import '../../models/skater_seat.dart';
import '../../services/penalty_engine.dart';
import '../box_timer_screen.dart';

/// Keeps timer-view changes in one route so switching is immediate.
class TimerViewHost extends StatelessWidget {
  final PenaltyEngine engine;

  const TimerViewHost({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PenaltyBoxState>();
    final onViewSelected = state.setTimerView;
    return switch (state.role) {
      AppRole.pbm => PbmScreen(engine: engine, onViewSelected: onViewSelected),
      AppRole.solo => SoloScreen(
        engine: engine,
        onViewSelected: onViewSelected,
      ),
      AppRole.team1BlockersOnly ||
      AppRole.team1Full ||
      AppRole.team2Full ||
      AppRole.team2BlockersOnly => BoxTimerScreen(
        engine: engine,
        onViewSelected: onViewSelected,
      ),
    };
  }
}

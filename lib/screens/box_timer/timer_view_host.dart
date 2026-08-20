import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    return _TimerViewOrientation(
      allowLandscape: state.role == AppRole.pbm,
      child: switch (state.role) {
        AppRole.pbm => PbmScreen(
          engine: engine,
          onViewSelected: onViewSelected,
        ),
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
      },
    );
  }
}

class _TimerViewOrientation extends StatefulWidget {
  final bool allowLandscape;
  final Widget child;

  const _TimerViewOrientation({
    required this.allowLandscape,
    required this.child,
  });

  @override
  State<_TimerViewOrientation> createState() => _TimerViewOrientationState();
}

class _TimerViewOrientationState extends State<_TimerViewOrientation> {
  @override
  void initState() {
    super.initState();
    _setPreferredOrientations();
  }

  @override
  void didUpdateWidget(covariant _TimerViewOrientation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.allowLandscape != oldWidget.allowLandscape) {
      _setPreferredOrientations();
    }
  }

  @override
  void dispose() {
    _setPortraitOnly();
    super.dispose();
  }

  void _setPreferredOrientations() {
    SystemChrome.setPreferredOrientations(
      widget.allowLandscape ? DeviceOrientation.values : _portraitOrientations,
    );
  }

  void _setPortraitOnly() {
    SystemChrome.setPreferredOrientations(_portraitOrientations);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

const _portraitOrientations = [
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
];

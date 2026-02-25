part of '../jam_timer_screen.dart';

extension _JamTimerLogic on _JamTimerScreenState {
  Clock _determineActiveClock(ScoreboardState state) {
    // Priority 1: Jam Clock - running OR InJam flag is true
    if (state.clocks['Jam']!.running || state.inJam) {
      return state.clocks['Jam']!;
    }

    // Priority 2: Lineup Clock - running
    if (state.clocks['Lineup']!.running) {
      return state.clocks['Lineup']!;
    }

    // Priority 3: Timeout Clock - running
    if (state.clocks['Timeout']!.running) {
      return state.clocks['Timeout']!;
    }

    // Fall through to Period/Intermission
    if (state.clocks['Intermission']!.running) {
      return state.clocks['Intermission']!;
    }

    // Default: show Lineup
    return state.clocks['Lineup']!;
  }

  String _formatTime(int milliseconds) {
    int seconds = (milliseconds / 1000).ceil();
    int minutes = (seconds / 60).floor();
    int remainingSeconds = (seconds % 60);
    return "${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
  }

  bool _isReadyToStart(ScoreboardState state) {
    final intermission = state.clocks['Intermission'];
    final lineup = state.clocks['Lineup'];
    final period = state.clocks['Period'];

    if (lineup == null || lineup.running) return false;
    if (period == null || period.running) return false;

    // Pre-game: Period 0
    if (period.number == 0 && !lineup.running) {
      return true;
    }

    // Post-intermission
    if (intermission != null &&
        !intermission.running &&
        intermission.time == 0 &&
        intermission.number > 0) {
      return true;
    }

    return false;
  }

  bool _isPrePeriod(ScoreboardState state) {
    if (state.clocks['Period']?.number == 0) return true;
    if (state.clocks['Intermission']?.running == true) return true;
    if (_isReadyToStart(state)) return true;

    bool anyClockRunning = state.clocks.values.any((c) => c.running);
    bool inTimeout = state.clocks['Timeout']!.running;

    if (!anyClockRunning && !state.inJam && !inTimeout) {
      return true;
    }
    return false;
  }
}

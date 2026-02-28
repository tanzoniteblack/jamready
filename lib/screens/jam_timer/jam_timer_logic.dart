part of '../jam_timer_screen.dart';

extension _JamTimerLogic on _JamTimerScreenState {
  Clock _determineActiveClock(ScoreboardState state) {
    // Priority 1: Jam clock while jam is in progress (even if jam clock is 0).
    if (state.clocks['Jam']!.running || state.inJam) {
      return state.clocks['Jam']!;
    }

    // Priority 2: Timeout clock.
    if (state.inTimeout || state.clocks['Timeout']!.running) {
      return state.clocks['Timeout']!;
    }

    // Priority 3: Lineup clock.
    if (state.clocks['Lineup']!.running) {
      return state.clocks['Lineup']!;
    }

    // Priority 4: Intermission clock (except post-game final state).
    if (state.clocks['Intermission']!.running && !state.noMoreJam) {
      return state.clocks['Intermission']!;
    }

    // Fallback: period clock when no active primary phase.
    if (state.clocks['Period']!.running || state.clocks['Period']!.time > 0) {
      return state.clocks['Period']!;
    }

    // Last resort.
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
    final jam = state.clocks['Jam'];
    final timeout = state.clocks['Timeout'];

    if (state.noMoreJam) return false;
    if (state.inJam || state.inTimeout) return false;
    if (jam == null || timeout == null || lineup == null || period == null) {
      return false;
    }
    if (jam.running ||
        timeout.running ||
        lineup.running ||
        intermission?.running == true) {
      return false;
    }

    if (period.running) return false;

    // Pre-game: Period 0
    if (period.number == 0) {
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
    if (!_isReadyToStart(state)) return false;

    // Use slider only for true pre-period lineup starts.
    if (state.clocks['Period']?.number == 0) return true;
    return state.labelStart.toLowerCase().contains('lineup');
  }

  bool _isGameOver(ScoreboardState state) {
    if (!state.noMoreJam) return false;
    if (state.inJam || state.clocks['Jam']?.running == true) return false;
    if (state.inTimeout || state.clocks['Timeout']?.running == true) {
      return false;
    }
    return true;
  }
}

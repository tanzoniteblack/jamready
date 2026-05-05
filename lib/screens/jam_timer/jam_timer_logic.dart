part of '../jam_timer_screen.dart';

extension _JamTimerLogic on _JamTimerScreenState {
  Clock _determineActiveClock(ScoreboardState state) {
    final lineupRunning = state.clocks['Lineup']!.running;
    final timeoutRunning = state.clocks['Timeout']!.running;

    // Priority 1: Jam clock while jam is in progress (even if jam clock is 0).
    if (state.clocks['Jam']!.running || state.inJam) {
      return state.clocks['Jam']!;
    }

    // Priority 2: CRG "SecondLineup" overlap (lineup + timeout running).
    // In this state, lineup is the primary clock while timeout still exists.
    if (lineupRunning && timeoutRunning) {
      return state.clocks['Lineup']!;
    }

    // Priority 3: Timeout clock.
    if (timeoutRunning) {
      return state.clocks['Timeout']!;
    }

    // Priority 4: Lineup clock.
    if (lineupRunning) {
      return state.clocks['Lineup']!;
    }

    // Priority 5: Intermission clock (except post-game final state).
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

    // noMoreJam only blocks ready-to-start when we're truly done with the game.
    // When the period count is known and there are still periods to play
    // (intermission number < total periods), noMoreJam is a transient flag
    // set at the end of each period, not a game-over signal.
    final isBetweenPeriods =
        state.periodCount > 0 &&
        !state.officialScore &&
        (intermission?.number ?? 0) < state.periodCount;
    if (state.noMoreJam && !isBetweenPeriods) return false;
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

  /// Pre-game countdown: Intermission is running before the first period.
  /// The server sets Intermission.Number = 0 for the pre-game countdown and
  /// Period.Number = 0 until the first period starts.
  bool _isPreGameCountdown(ScoreboardState state) {
    final intermission = state.clocks['Intermission'];
    final period = state.clocks['Period'];
    if (intermission == null || period == null) return false;
    if (intermission.number != 0 || !intermission.running) return false;
    if (period.number != 0) return false;
    if (state.inJam || state.noMoreJam) return false;
    return true;
  }

  /// Halftime (or between-period) intermission: Intermission is actively
  /// running after at least one period has been played, but the game is not
  /// yet over.
  bool _isHalftimeIntermission(ScoreboardState state) {
    final intermission = state.clocks['Intermission'];
    if (intermission == null) return false;
    if (!intermission.running || intermission.number == 0) return false;
    if (state.inJam || state.officialScore) return false;

    // When the period count is known, use it precisely: this is halftime only
    // when the intermission number hasn't reached the final period yet.
    if (state.periodCount > 0) {
      return intermission.number < state.periodCount;
    }

    // Fall back: noMoreJam marks the post-game intermission when period
    // count isn't known yet.
    return !state.noMoreJam;
  }

  bool _isPrePeriod(ScoreboardState state) {
    if (_isPreGameCountdown(state)) return true;
    // Note: _isHalftimeIntermission is intentionally NOT checked here.
    // While the intermission clock is still running the controls are locked
    // out entirely; the slider only appears once the clock has finished.
    if (!_isReadyToStart(state)) return false;

    // Period hasn't started yet (pre-game).
    if (state.clocks['Period']?.number == 0) return true;

    // Post-intermission: the countdown or halftime break just ended.
    // _isReadyToStart uses this same condition to recognise this state.
    final intermission = state.clocks['Intermission'];
    if (intermission != null &&
        !intermission.running &&
        intermission.time == 0 &&
        intermission.number > 0) {
      return true;
    }

    return state.labelStart.toLowerCase().contains('lineup');
  }

  /// Post-regulation: the final-period intermission is running (or has ended)
  /// but the score has not yet been confirmed by the NSO. This includes the
  /// tied-game/overtime-possible case (noMoreJam=false) as well as the
  /// definitive-end case (noMoreJam=true).
  bool _isUnofficialScore(ScoreboardState state) {
    if (state.officialScore) return false;
    if (state.inJam || state.clocks['Jam']?.running == true) return false;
    if (state.clocks['Lineup']?.running == true) return false;
    if (state.inTimeout || state.clocks['Timeout']?.running == true) {
      return false;
    }

    // When the period count is known, detect via Intermission.Number.
    // Show unofficial score while the final intermission is still running, OR
    // after it has ended (noMoreJam confirms we are truly post-game).
    if (state.periodCount > 0) {
      final intermissionClock = state.clocks['Intermission'];
      if (intermissionClock == null) return false;
      if (intermissionClock.number < state.periodCount) return false;
      return intermissionClock.running || state.noMoreJam;
    }

    // Fall back to noMoreJam when period count is not yet known.
    return state.noMoreJam;
  }

  /// True only when the officials have confirmed the score is official.
  /// Use [_isUnofficialScore] for the post-game-but-not-yet-confirmed state.
  bool _isGameOver(ScoreboardState state) {
    return state.officialScore;
  }
}

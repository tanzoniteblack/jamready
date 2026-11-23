import 'dart:async';
import 'dart:math';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/game_config.dart';
import '../models/ruleset.dart';
import '../models/scoreboard_state.dart';
import 'game_engine.dart';

/// Game phase representing the current state of play.
enum GamePhase {
  /// Before the game starts
  preGame,

  /// Between jams (lineup clock running)
  lineup,

  /// During a jam
  jam,

  /// During a timeout
  timeout,

  /// Between periods
  intermission,

  /// Final period has ended; waiting for overtime or end-game decision.
  unofficialScore,

  /// Game has ended
  gameOver,
}

/// Local game engine for offline play.
///
/// Uses Timer.periodic for smooth clock updates. Handles:
/// - Countdown clocks (Jam, Period, Intermission) - subtract elapsed time
/// - Countup clocks (Lineup, Timeout) - add elapsed time
/// - Background timing via WidgetsBindingObserver
class LocalGameEngine with WidgetsBindingObserver implements GameEngine {
  final ScoreboardState _state;
  final GameConfig _config;

  Timer? _tickTimer;

  // Monotonic time source for ticks. Elapsed time is derived from the
  // stopwatch's running total so sub-millisecond remainders are never lost.
  Stopwatch _tickStopwatch = clock.stopwatch();
  int _lastTickTotalMs = 0;
  DateTime? _backgroundedAt;
  bool _isActive = false;

  GamePhase _phase = GamePhase.preGame;

  /// Set when a timeout is called after the period has ended (intermission or
  /// unofficial score), so ending the timeout can return to that phase.
  GamePhase? _postPeriodPhase;
  int _currentPeriod = 0;
  int _currentJam = 0;

  // Internal clock state (precise millisecond values)
  final Map<String, int> _internalClockTimes = {};

  // Clock snapshot for background timing
  Map<String, int>? _backgroundClockSnapshot;
  Map<String, bool>? _backgroundRunningSnapshot;

  // Undo support - stores the last undoable action
  _UndoAction? _lastAction;
  DateTime? _actionTimestamp;

  LocalGameEngine(this._state, this._config);

  Ruleset get ruleset => _config.ruleset;

  @override
  bool get isActive => _isActive;

  @override
  ScoreboardState get state => _state;

  @override
  bool get supportsUndo => true;

  @override
  bool get isLocal => true;

  GamePhase get phase => _phase;

  @override
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);

    // Initialize state with game config
    _state.team1.name = _config.team1Name;
    _state.team1.alternateName = '';
    _state.team2.name = _config.team2Name;
    _state.team2.alternateName = '';
    _state.team1.colorBg = '';
    _state.team1.colorFg = '';
    _state.team2.colorBg = '';
    _state.team2.colorFg = '';
    _applyDefaultLocalTeamColors();

    // Reset scores
    _state.team1.score = 0;
    _state.team2.score = 0;

    // Set timeouts and reviews
    _state.team1.timeouts = ruleset.timeoutsPerPeriod;
    _state.team1.officialReviews = ruleset.reviewsPerPeriod;
    _state.team1.retainedOfficialReview = false;
    _state.team2.timeouts = ruleset.timeoutsPerPeriod;
    _state.team2.officialReviews = ruleset.reviewsPerPeriod;
    _state.team2.retainedOfficialReview = false;

    // Initialize clocks
    _initializeClocks();

    // Set labels
    _state.labelStart = "Start Jam";
    _state.labelStop = "Stop Jam";
    _state.labelTimeout = "Timeout";
    _state.labelUndo = "No Action";
    _state.labelReplaced = "";

    // Set rules
    _state.lineupDuration = ruleset.lineupDurationMs;
    _state.lineupOvertimeDuration = ruleset.lineupOvertimeDurationMs;
    _state.periodCount = ruleset.periodCount;

    // Game state flags
    _state.inJam = false;
    _state.noMoreJam = false;
    _state.inOvertime = false;
    _state.timeoutOwner = "";
    _state.officialReview = "false";

    _state.setConnectionStatus("Offline Game");
    _isActive = true;

    // Keep screen awake
    WakelockPlus.enable();

    // Start the tick timer (60fps = ~16ms interval)
    _startTickTimer();

    _state.notify();
  }

  void _applyDefaultLocalTeamColors() {
    void setColorsForTeam(Team team) {
      switch (team.name.trim().toLowerCase()) {
        case 'salt':
          team.colorBg = 'F2F2F2';
          team.colorFg = '1A1A1A';
          break;
        case 'pepper':
          team.colorBg = '2E2E2E';
          team.colorFg = 'F5F5F5';
          break;
      }
    }

    setColorsForTeam(_state.team1);
    setColorsForTeam(_state.team2);
  }

  void _initializeClocks() {
    // Period clock - starts at period duration, counts down
    final periodTime = _getDisplayTime(ruleset.periodDurationMs, false);
    _state.clocks['Period']!.time = periodTime;
    _internalClockTimes['Period'] = periodTime;
    _state.clocks['Period']!.running = false;
    _state.clocks['Period']!.number = 0;
    _state.clocks['Period']!.displayName = "Period";

    // Jam clock - starts at jam duration, counts down
    final jamTime = _getDisplayTime(ruleset.jamDurationMs, false);
    _state.clocks['Jam']!.time = jamTime;
    _internalClockTimes['Jam'] = jamTime;
    _state.clocks['Jam']!.running = false;
    _state.clocks['Jam']!.number = 0;
    _state.clocks['Jam']!.displayName = "Jam";

    // Lineup clock - starts at 0, counts up
    _state.clocks['Lineup']!.time = 0;
    _internalClockTimes['Lineup'] = 0;
    _state.clocks['Lineup']!.running = false;
    _state.clocks['Lineup']!.number = 0;
    _state.clocks['Lineup']!.displayName = "Lineup";

    // Timeout clock - starts at 0, counts up
    _state.clocks['Timeout']!.time = 0;
    _internalClockTimes['Timeout'] = 0;
    _state.clocks['Timeout']!.running = false;
    _state.clocks['Timeout']!.number = 0;
    _state.clocks['Timeout']!.displayName = "Timeout";

    // Intermission clock - varies by ruleset
    _state.clocks['Intermission']!.time = 0;
    _internalClockTimes['Intermission'] = 0;
    _state.clocks['Intermission']!.running = false;
    _state.clocks['Intermission']!.number = 0;
    _state.clocks['Intermission']!.displayName = "Intermission";
  }

  void _startTickTimer() {
    _tickTimer?.cancel();
    _tickStopwatch = clock.stopwatch()..start();
    _lastTickTotalMs = 0;
    _tickTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _tick();
    });
  }

  void _tick() {
    final totalMs = _tickStopwatch.elapsedMilliseconds;
    final elapsed = totalMs - _lastTickTotalMs;
    _lastTickTotalMs = totalMs;

    var displayChanged = false;

    // Update internal times for all running clocks
    for (final entry in _state.clocks.entries) {
      final clock = entry.value;
      if (!clock.running) continue;

      final clockName = entry.key;
      final isCountUp = _isCountUp(clockName);

      // Update internal precise time
      int newInternalTime = _internalClockTimes[clockName] ?? clock.time;
      if (isCountUp) {
        newInternalTime += elapsed;
      } else {
        newInternalTime -= elapsed;
        if (newInternalTime < 0) newInternalTime = 0;
      }
      _internalClockTimes[clockName] = newInternalTime;

      // Each clock updates its display as soon as its own displayed second
      // changes, so clocks never lag and are never nudged into sync with each
      // other (which would alter jam/lineup/timeout durations).
      final displayTime = _getDisplayTime(newInternalTime, isCountUp);
      if (displayTime != clock.time) {
        clock.time = displayTime;
        displayChanged = true;
      }

      // Handle clock expiration (using internal time for precision)
      if (!isCountUp && newInternalTime <= 0) {
        _handleClockExpiration(clockName);
      }
    }

    if (displayChanged) {
      _checkUndoValidity();
      _state.notify();
    }
  }

  /// Check if the current undo action is still valid.
  /// For unstop jam, if elapsed time would make jam clock <= 0, invalidate it.
  void _checkUndoValidity() {
    if (_lastAction == null || _actionTimestamp == null) return;

    if (_lastAction!.type == _UndoType.unstopJam) {
      final elapsed = clock.now().difference(_actionTimestamp!).inMilliseconds;
      final projectedJamTime = (_lastAction!.jamTimeInternal ?? 0) - elapsed;

      if (projectedJamTime <= 0) {
        _clearUndo();
      }
    }
  }

  /// Get display time for a clock.
  /// - Countup clocks: floor to current full second
  /// - Countdown clocks: ceil to next full second
  int _getDisplayTime(int internalMs, bool isCountUp) {
    if (isCountUp) {
      // Floor to current second
      return (internalMs / 1000).floor() * 1000;
    } else {
      // Ceil to next second
      return (internalMs / 1000).ceil() * 1000;
    }
  }

  static bool _isCountUp(String clockName) =>
      clockName == 'Lineup' || clockName == 'Timeout';

  void _handleClockExpiration(String clockName) {
    switch (clockName) {
      case 'Jam':
        _endJam(fromExpiration: true);
        break;
      case 'Period':
        _endPeriod(jamIsRunning: _phase == GamePhase.jam);
        break;
      case 'Intermission':
        _endIntermission();
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _onBackgrounded();
    } else if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  void _onBackgrounded() {
    _backgroundedAt = clock.now();
    _tickTimer?.cancel();

    // Snapshot clock states (use internal time for precision)
    _backgroundClockSnapshot = {};
    _backgroundRunningSnapshot = {};
    for (final entry in _state.clocks.entries) {
      _backgroundClockSnapshot![entry.key] = _internalClockTimes[entry.key] ?? entry.value.time;
      _backgroundRunningSnapshot![entry.key] = entry.value.running;
    }
  }

  void _onResumed() {
    if (_backgroundedAt == null || _backgroundClockSnapshot == null) {
      _startTickTimer();
      return;
    }

    final elapsed = clock.now().difference(_backgroundedAt!).inMilliseconds;
    _backgroundedAt = null;

    // Reconstruct clock states
    for (final entry in _state.clocks.entries) {
      final clockName = entry.key;
      final clock = entry.value;
      final wasRunning = _backgroundRunningSnapshot?[clockName] ?? false;

      if (!wasRunning) continue;

      final snapshotTime = _backgroundClockSnapshot![clockName]!;
      final isCountUp = _isCountUp(clockName);

      int newInternalTime;
      if (isCountUp) {
        newInternalTime = snapshotTime + elapsed;
      } else {
        newInternalTime = snapshotTime - elapsed;
        if (newInternalTime < 0) newInternalTime = 0;

        // Handle expirations that occurred during background
        if (newInternalTime <= 0 && snapshotTime > 0) {
          _handleClockExpiration(clockName);
        }
      }

      // Update internal time and display time
      _internalClockTimes[clockName] = newInternalTime;
      clock.time = _getDisplayTime(newInternalTime, isCountUp);
    }

    _backgroundClockSnapshot = null;
    _backgroundRunningSnapshot = null;

    _startTickTimer();
    _state.notify();
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _tickTimer?.cancel();
    _isActive = false;
    WakelockPlus.disable();
  }

  // Game control methods

  @override
  void startJam() {
    if (_phase == GamePhase.preGame && _currentPeriod == 0) {
      // First jam of game - start period 1
      _startPeriod(1);
    }

    if (_phase == GamePhase.intermission) {
      // Intermission ended, start next period
      _endIntermission();
    }

    if (_phase != GamePhase.lineup && _phase != GamePhase.preGame) {
      return;
    }

    // Record undo state before starting jam
    _setUndoAction(
      _UndoType.unstartJam,
      lineupTime: _state.clocks['Lineup']!.time,
      lineupTimeInternal: _internalClockTimes['Lineup'],
      periodTime: _state.clocks['Period']!.time,
      periodTimeInternal: _internalClockTimes['Period'],
      periodWasRunning: _state.clocks['Period']!.running,
    );

    // Stop lineup clock
    _state.clocks['Lineup']!.running = false;

    // Start jam
    _currentJam++;
    final jamTime = _getDisplayTime(ruleset.jamDurationMs, false);
    _state.clocks['Jam']!.time = jamTime;
    _internalClockTimes['Jam'] = jamTime;
    _state.clocks['Jam']!.number = _currentJam;
    _state.clocks['Jam']!.running = true;
    // Overtime jams have no period clock — it already expired.
    if (!_state.inOvertime) {
      _state.clocks['Period']!.running = true;
    }

    _state.inJam = true;
    _phase = GamePhase.jam;

    _state.labelStart = "Start Jam";
    _state.labelStop = "Stop Jam";

    _state.notify();
  }

  @override
  void stopJam() {
    if (_phase == GamePhase.preGame) {
      // Record undo state for "unstart lineup".
      // periodNumber captures where we'll return to on undo — 0 for the
      // initial pre-game, or the already-prepared period number when coming
      // out of an intermission (where _startPeriod has already been called).
      _setUndoAction(
        _UndoType.unstartLineup,
        periodTime: _state.clocks['Period']!.time,
        periodTimeInternal: _internalClockTimes['Period'],
        periodNumber: _currentPeriod,
      );

      // Period 0 → first swipe of the game: begin period 1 now.
      // Any later period is already prepared by _endIntermission.
      if (_currentPeriod == 0) {
        _startPeriod(1);
      }
      _startLineup();
      return;
    }

    if (_phase == GamePhase.unofficialScore) {
      // User chose overtime — start an overtime lineup.
      _state.inOvertime = true;
      _state.noMoreJam = false;
      _state.clocks['Lineup']!.time = 0;
      _internalClockTimes['Lineup'] = 0;
      _state.clocks['Lineup']!.running = true;
      _phase = GamePhase.lineup;
      _state.notify();
      return;
    }

    if (_phase == GamePhase.jam) {
      _endJam();
    } else if (_phase == GamePhase.timeout) {
      endTimeout();
    }
  }

  @override
  void endGame() {
    _state.clocks['Jam']!.running = false;
    _state.clocks['Period']!.running = false;
    _state.clocks['Lineup']!.running = false;
    _state.clocks['Timeout']!.running = false;
    _state.inJam = false;
    _state.noMoreJam = true;
    _state.officialScore = true;
    _phase = GamePhase.gameOver;
    _state.setConnectionStatus("Game Over");
    _state.notify();
  }

  void _endJam({bool fromExpiration = false}) {
    _state.clocks['Jam']!.running = false;
    _state.inJam = false;

    // Check if period ended (period expired while jam was running).
    // Overtime jams have no period clock, so skip this check.
    if (!_state.inOvertime && _state.clocks['Period']!.time <= 0) {
      if (!fromExpiration) {
        // Period ended because this jam was manually stopped – save undo so
        // the operator can restore both the jam and the period.
        _setUndoAction(
          _UndoType.unstopJam,
          jamTime: _state.clocks['Jam']!.time,
          jamTimeInternal: _internalClockTimes['Jam'],
          periodWasRunning: false,
          periodEndedDuringJam: true,
          wasGameOver: _currentPeriod >= ruleset.periodCount,
        );
      } else {
        _clearUndo();
      }
      _endPeriod();
      return;
    }

    // Normal jam end
    if (!fromExpiration) {
      _setUndoAction(
        _UndoType.unstopJam,
        jamTime: _state.clocks['Jam']!.time,
        jamTimeInternal: _internalClockTimes['Jam'],
        periodTimeInternal: _internalClockTimes['Period'],
        periodWasRunning: _state.clocks['Period']!.running,
      );
    } else {
      _clearUndo();
    }

    if (_state.inOvertime) {
      // After an overtime jam, return to unofficial score so the operator can
      // decide to run another overtime jam or end the game.
      // Reset noMoreJam=true: stopJam() cleared it when entering overtime, but
      // _isUnofficialScore needs it true to detect this state correctly.
      _state.noMoreJam = true;
      _phase = GamePhase.unofficialScore;
      _state.notify();
    } else {
      _startLineup();
    }
  }

  void _startLineup() {
    _state.clocks['Lineup']!.time = 0;
    _internalClockTimes['Lineup'] = 0;
    _state.clocks['Lineup']!.running = true;

    _phase = GamePhase.lineup;
    _state.labelStart = "Start Jam";
    _state.labelStop = "Stop Jam";

    _state.notify();
  }

  void _startPeriod(int periodNumber) {
    _currentPeriod = periodNumber;
    _state.clocks['Period']!.number = periodNumber;

    // Only reset period clock time for periods after the first
    // (coming from intermission). For period 1, preserve any user adjustments.
    if (periodNumber > 1) {
      final periodTime = _getDisplayTime(ruleset.periodDurationMs, false);
      _state.clocks['Period']!.time = periodTime;
      _internalClockTimes['Period'] = periodTime;
    }
    _state.clocks['Period']!.displayName = "Period";

    // Reset jam number if ruleset requires it
    if (ruleset.jamsResetPerPeriod && periodNumber > 1) {
      _currentJam = 0;
    }

    // Reset timeouts and official reviews for new period
    _state.team1.timeouts = ruleset.timeoutsPerPeriod;
    _state.team2.timeouts = ruleset.timeoutsPerPeriod;
    _state.team1.officialReviews = ruleset.reviewsPerPeriod;
    _state.team2.officialReviews = ruleset.reviewsPerPeriod;
    _state.team1.retainedOfficialReview = false;
    _state.team2.retainedOfficialReview = false;

    _phase = GamePhase.lineup;
    _state.notify();
  }

  void _endPeriod({bool jamIsRunning = false}) {
    if (jamIsRunning) {
      // Period expired while a jam is live. Stop the period clock but leave
      // the jam running — WFTDA rules require the jam to continue until the
      // next whistle. _endJam will call _endPeriod again (without this flag)
      // once the jam is stopped.
      _state.clocks['Period']!.running = false;
      _state.notify();
      return;
    }

    _state.clocks['Jam']!.running = false;
    _state.clocks['Period']!.running = false;
    _state.clocks['Lineup']!.running = false;
    _state.inJam = false;

    if (_currentPeriod >= ruleset.periodCount) {
      // Final period ended — wait for the user to choose overtime or end game.
      // Set intermission.number = periodCount so _isUnofficialScore's
      // period-count path recognises this state correctly.
      _state.clocks['Intermission']!.number = _currentPeriod;
      _state.noMoreJam = true;
      _phase = GamePhase.unofficialScore;
      _state.notify();
      return;
    }

    // Start intermission
    final intermissionDuration = _getDisplayTime(
        ruleset.getIntermissionDurationMs(_currentPeriod), false);
    _state.clocks['Intermission']!.time = intermissionDuration;
    _internalClockTimes['Intermission'] = intermissionDuration;
    _state.clocks['Intermission']!.number = _currentPeriod;
    _state.clocks['Intermission']!.running = true;
    _state.clocks['Intermission']!.displayName = "Intermission";

    _phase = GamePhase.intermission;
    _state.notify();
  }

  void _endIntermission() {
    _state.clocks['Intermission']!.running = false;
    _state.clocks['Intermission']!.time = 0;
    _internalClockTimes['Intermission'] = 0;

    // Prepare the next period but wait for the user to swipe to start lineup,
    // mirroring the CRG remote flow. _startPeriod sets phase = lineup as a
    // side effect; we override it back to preGame so the layout shows READY.
    _startPeriod(_currentPeriod + 1);
    _phase = GamePhase.preGame;
    _state.notify();
  }

  @override
  void startTimeout() {
    if (_phase == GamePhase.jam) {
      _endJam();
    }

    // A timeout after the period has ended (e.g. requested as the period
    // clock expired — WFTDA Officiating Procedures §4.7 — or an Official
    // Review after the final jam) pauses the intermission, matching CRG.
    if (_phase == GamePhase.intermission ||
        _phase == GamePhase.unofficialScore) {
      _postPeriodPhase = _phase;
      _state.clocks['Intermission']!.running = false;
    }

    // Stop lineup clock
    _state.clocks['Lineup']!.running = false;
    _state.clocks['Period']!.running = false;

    // Start timeout clock
    _state.clocks['Timeout']!.time = 0;
    _internalClockTimes['Timeout'] = 0;
    _state.clocks['Timeout']!.running = true;

    _phase = GamePhase.timeout;
    _state.labelStop = "End Timeout";
    _state.timeoutOwner = "O"; // Default to official timeout

    _state.notify();
  }

  @override
  void endTimeout() {
    _state.clocks['Timeout']!.running = false;
    _state.timeoutOwner = "";
    _state.officialReview = "false";

    final postPeriodPhase = _postPeriodPhase;
    _postPeriodPhase = null;

    if (postPeriodPhase != null && _internalClockTimes['Period']! <= 0) {
      // Period is still over: go back to the intermission / unofficial score.
      _phase = postPeriodPhase;
      _state.clocks['Intermission']!.running =
          postPeriodPhase == GamePhase.intermission;
      _state.notify();
      return;
    }

    if (postPeriodPhase != null) {
      // The operator put time back on the period clock during the timeout
      // (§4.7), so the period resumes: cancel the intermission and line up
      // for another jam in this period.
      _resumeEndedPeriod();
    }

    // Return to lineup
    _startLineup();
  }

  /// Undoes the intermission bookkeeping done by [_endPeriod] so play can
  /// continue in the current period.
  void _resumeEndedPeriod() {
    final intermission = _state.clocks['Intermission']!;
    intermission.running = false;
    intermission.time = 0;
    intermission.number = _currentPeriod - 1;
    _internalClockTimes['Intermission'] = 0;
    _state.noMoreJam = false;
  }

  @override
  void setTimeoutOwner(String owner, {bool isOfficialReview = false}) {
    // Capture previous owner before potentially starting a new timeout.
    // If we're already in a timeout, we'll need to restore their resource.
    final prevOwner = _state.timeoutOwner;
    final prevIsOr = _state.isOfficialReview;

    if (_phase != GamePhase.timeout) {
      // Start timeout first
      startTimeout();
    }

    // Restore resources for the previous team owner (if any) before applying
    // the new assignment. This handles re-assignment mid-timeout, e.g.:
    //   assign team 1 TO → switch to official TO → team 1's count comes back.
    if (prevOwner == '1') {
      if (prevIsOr) {
        _state.team1.officialReviews++;
      } else {
        _state.team1.timeouts++;
      }
    } else if (prevOwner == '2') {
      if (prevIsOr) {
        _state.team2.officialReviews++;
      } else {
        _state.team2.timeouts++;
      }
    }

    // Decrement resources
    if (owner == '1') {
      if (isOfficialReview) {
        if (_state.team1.officialReviews > 0) {
          _state.team1.officialReviews--;
        }
        _state.officialReview = "true";
        _state.timeoutOwner = '1';
      } else {
        if (_state.team1.timeouts > 0) {
          _state.team1.timeouts--;
        }
        _state.officialReview = "false";
        _state.timeoutOwner = '1';
      }
    } else if (owner == '2') {
      if (isOfficialReview) {
        if (_state.team2.officialReviews > 0) {
          _state.team2.officialReviews--;
        }
        _state.officialReview = "true";
        _state.timeoutOwner = '2';
      } else {
        if (_state.team2.timeouts > 0) {
          _state.team2.timeouts--;
        }
        _state.officialReview = "false";
        _state.timeoutOwner = '2';
      }
    } else {
      // Official timeout
      _state.timeoutOwner = "O";
      _state.officialReview = "false";
    }

    _state.notify();
  }

  @override
  void adjustClock(String clockName, int deltaMs) {
    final clock = _state.clocks[clockName];
    if (clock == null) return;

    // Update internal time
    final currentInternal = _internalClockTimes[clockName] ?? clock.time;
    int newInternal = currentInternal + deltaMs;
    if (newInternal < 0) newInternal = 0;

    _internalClockTimes[clockName] = newInternal;

    // Update display time
    final isCountUp = _isCountUp(clockName);
    clock.time = _getDisplayTime(newInternal, isCountUp);

    _state.notify();
  }

  @override
  void setClockTime(String clockName, int timeMs) {
    final clock = _state.clocks[clockName];
    if (clock == null) return;

    // Set internal time directly
    int newInternal = timeMs;
    if (newInternal < 0) newInternal = 0;

    _internalClockTimes[clockName] = newInternal;

    // Update display time
    final isCountUp = _isCountUp(clockName);
    clock.time = _getDisplayTime(newInternal, isCountUp);

    _state.notify();
  }

  @override
  void adjustScore(int teamNumber, int delta) {
    if (teamNumber == 1) {
      _state.team1.score += delta;
      if (_state.team1.score < 0) _state.team1.score = 0;
    } else if (teamNumber == 2) {
      _state.team2.score += delta;
      if (_state.team2.score < 0) _state.team2.score = 0;
    }

    _state.notify();
  }

  @override
  void setRetainedReview(int teamNumber, bool retained) {
    if (teamNumber == 1) {
      _state.team1.retainedOfficialReview = retained;
      if (retained && _state.team1.officialReviews < ruleset.reviewsPerPeriod) {
        _state.team1.officialReviews++;
      }
    } else if (teamNumber == 2) {
      _state.team2.retainedOfficialReview = retained;
      if (retained && _state.team2.officialReviews < ruleset.reviewsPerPeriod) {
        _state.team2.officialReviews++;
      }
    }

    _state.notify();
  }

  @override
  void undo() {
    if (_lastAction == null || _actionTimestamp == null) return;

    final action = _lastAction!;
    final elapsed = clock.now().difference(_actionTimestamp!).inMilliseconds;

    _lastAction = null;
    _actionTimestamp = null;
    _state.labelUndo = "No Action";

    switch (action.type) {
      case _UndoType.unstopJam:
        // If the undo fires while still in a timeout (operator hit undo before
        // ending the timeout), restore the assigned team's resources and clear
        // the timeout state before reinstating the jam.
        if (_phase == GamePhase.timeout) {
          final owner = _state.timeoutOwner;
          final wasOr = _state.isOfficialReview;
          if (owner == '1') {
            if (wasOr) { _state.team1.officialReviews++; }
            else { _state.team1.timeouts++; }
          } else if (owner == '2') {
            if (wasOr) { _state.team2.officialReviews++; }
            else { _state.team2.timeouts++; }
          }
          _state.timeoutOwner = "";
          _state.officialReview = "false";
          _state.clocks['Timeout']!.running = false;
          _postPeriodPhase = null;
        }

        // Calculate jam time accounting for elapsed time since stop
        final newJamTimeInternal = (action.jamTimeInternal ?? 0) - elapsed;

        // Don't allow undo if jam would have expired
        if (newJamTimeInternal <= 0) return;

        final newJamTime = _getDisplayTime(newJamTimeInternal, false);

        if (action.periodEndedDuringJam == true) {
          // The jam stop also ended the period. Reverse the period end first.
          if (action.wasGameOver == true) {
            _state.noMoreJam = false;
            _state.setConnectionStatus("Offline Game");
          } else {
            // Reverse intermission
            _state.clocks['Intermission']!.running = false;
            _state.clocks['Intermission']!.time = 0;
            _internalClockTimes['Intermission'] = 0;
          }
          // Period remains at 0 and not running – it had already expired
          _state.clocks['Period']!.time = 0;
          _internalClockTimes['Period'] = 0;
          _state.clocks['Period']!.running = false;
          _state.clocks['Lineup']!.running = false;
        } else {
          // Normal unstop. The period clock carries on as if the jam had never
          // stopped, even if a timeout has since stopped it.
          _state.clocks['Lineup']!.running = false;
          if (action.periodWasRunning == true) {
            _resumeClockAfter('Period', action.periodTimeInternal!, elapsed);
          }
        }

        // Restore jam state with adjusted time
        _state.clocks['Jam']!.time = newJamTime;
        _internalClockTimes['Jam'] = newJamTimeInternal;
        _state.clocks['Jam']!.running = true;
        _state.inJam = true;
        _phase = GamePhase.jam;
        _state.labelStop = "Stop Jam";
        break;

      case _UndoType.unstartJam:
        // Go back to lineup
        _state.clocks['Jam']!.running = false;
        if (!action.periodWasRunning!) {
          // The jam started the period clock; put back the time it ran.
          _state.clocks['Period']!.running = false;
          _state.clocks['Period']!.time = action.periodTime!;
          _internalClockTimes['Period'] = action.periodTimeInternal!;
        }
        // The lineup carries on as if the jam had never started.
        _resumeClockAfter('Lineup', action.lineupTimeInternal!, elapsed);
        _state.inJam = false;
        _currentJam--;
        _state.clocks['Jam']!.number = _currentJam;
        _phase = GamePhase.lineup;
        break;

      case _UndoType.unstartLineup:
        // Go back to pre-period state
        _state.clocks['Lineup']!.running = false;
        _state.clocks['Period']!.running = false;
        if (action.periodTime != null) {
          _state.clocks['Period']!.time = action.periodTime!;
          _internalClockTimes['Period'] = action.periodTimeInternal!;
        }
        _state.clocks['Period']!.number = action.periodNumber!;
        _currentPeriod = action.periodNumber!;
        _phase = GamePhase.preGame;
        break;
    }

    _state.notify();
  }

  /// Runs [clockName] from [internalMs] as if it had kept running for
  /// [elapsedMs]. Expiry is left to the next tick.
  void _resumeClockAfter(String clockName, int internalMs, int elapsedMs) {
    final isCountUp = _isCountUp(clockName);
    final newInternal = isCountUp
        ? internalMs + elapsedMs
        : max(0, internalMs - elapsedMs);
    _internalClockTimes[clockName] = newInternal;
    _state.clocks[clockName]!.time = _getDisplayTime(newInternal, isCountUp);
    _state.clocks[clockName]!.running = true;
  }

  void _clearUndo() {
    _lastAction = null;
    _actionTimestamp = null;
    _state.labelUndo = "No Action";
  }

  void _setUndoAction(_UndoType type, {
    int? jamTime,
    int? jamTimeInternal,
    int? lineupTime,
    int? lineupTimeInternal,
    int? periodTime,
    int? periodTimeInternal,
    int? periodNumber,
    bool? periodWasRunning,
    bool? periodEndedDuringJam,
    bool? wasGameOver,
  }) {
    _actionTimestamp = clock.now();
    _lastAction = _UndoAction(
      type: type,
      jamTime: jamTime,
      jamTimeInternal: jamTimeInternal,
      lineupTime: lineupTime,
      lineupTimeInternal: lineupTimeInternal,
      periodTime: periodTime,
      periodTimeInternal: periodTimeInternal,
      periodNumber: periodNumber,
      periodWasRunning: periodWasRunning,
      periodEndedDuringJam: periodEndedDuringJam,
      wasGameOver: wasGameOver,
    );

    switch (type) {
      case _UndoType.unstopJam:
        _state.labelUndo = "UNDO: Unstop Jam";
        break;
      case _UndoType.unstartJam:
        _state.labelUndo = "UNDO: Unstart Jam";
        break;
      case _UndoType.unstartLineup:
        _state.labelUndo = "UNDO: Unstart Lineup";
        break;
    }
  }
}

enum _UndoType {
  unstopJam,
  unstartJam,
  unstartLineup,
}

class _UndoAction {
  final _UndoType type;
  final int? jamTime;
  final int? jamTimeInternal;
  final int? lineupTime;
  final int? lineupTimeInternal;
  final int? periodTime;
  final int? periodTimeInternal;
  final int? periodNumber;
  final bool? periodWasRunning;
  final bool? periodEndedDuringJam;
  final bool? wasGameOver;

  _UndoAction({
    required this.type,
    this.jamTime,
    this.jamTimeInternal,
    this.lineupTime,
    this.lineupTimeInternal,
    this.periodTime,
    this.periodTimeInternal,
    this.periodNumber,
    this.periodWasRunning,
    this.periodEndedDuringJam,
    this.wasGameOver,
  });
}

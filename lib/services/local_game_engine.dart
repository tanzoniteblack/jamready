import 'dart:async';
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
  DateTime? _lastTickTime;
  DateTime? _backgroundedAt;
  bool _isActive = false;

  GamePhase _phase = GamePhase.preGame;
  int _currentPeriod = 0;
  int _currentJam = 0;

  // Clock snapshot for background timing
  Map<String, int>? _backgroundClockSnapshot;
  Map<String, bool>? _backgroundRunningSnapshot;

  LocalGameEngine(this._state, this._config);

  Ruleset get ruleset => _config.ruleset;

  @override
  bool get isActive => _isActive;

  @override
  ScoreboardState get state => _state;

  @override
  bool get supportsUndo => false;

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

    // Reset scores
    _state.team1.score = 0;
    _state.team2.score = 0;

    // Set timeouts and reviews
    _state.team1.timeouts = ruleset.timeoutsPerGame;
    _state.team1.officialReviews = ruleset.reviewsPerPeriod;
    _state.team1.retainedOfficialReview = false;
    _state.team2.timeouts = ruleset.timeoutsPerGame;
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

  void _initializeClocks() {
    // Period clock - starts at period duration, counts down
    _state.clocks['Period']!.time = ruleset.periodDurationMs;
    _state.clocks['Period']!.running = false;
    _state.clocks['Period']!.number = 0;
    _state.clocks['Period']!.displayName = "Period";

    // Jam clock - starts at jam duration, counts down
    _state.clocks['Jam']!.time = ruleset.jamDurationMs;
    _state.clocks['Jam']!.running = false;
    _state.clocks['Jam']!.number = 0;
    _state.clocks['Jam']!.displayName = "Jam";

    // Lineup clock - starts at 0, counts up
    _state.clocks['Lineup']!.time = 0;
    _state.clocks['Lineup']!.running = false;
    _state.clocks['Lineup']!.number = 0;
    _state.clocks['Lineup']!.displayName = "Lineup";

    // Timeout clock - starts at 0, counts up
    _state.clocks['Timeout']!.time = 0;
    _state.clocks['Timeout']!.running = false;
    _state.clocks['Timeout']!.number = 0;
    _state.clocks['Timeout']!.displayName = "Timeout";

    // Intermission clock - varies by ruleset
    _state.clocks['Intermission']!.time = 0;
    _state.clocks['Intermission']!.running = false;
    _state.clocks['Intermission']!.number = 0;
    _state.clocks['Intermission']!.displayName = "Intermission";
  }

  void _startTickTimer() {
    _tickTimer?.cancel();
    _lastTickTime = DateTime.now();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _tick();
    });
  }

  void _tick() {
    final now = DateTime.now();
    final elapsed = now.difference(_lastTickTime!).inMilliseconds;
    _lastTickTime = now;

    bool stateChanged = false;

    // Update each running clock
    for (final entry in _state.clocks.entries) {
      final clock = entry.value;
      if (!clock.running) continue;

      final clockName = entry.key;
      final isCountUp = clockName == 'Lineup' || clockName == 'Timeout';

      if (isCountUp) {
        clock.time += elapsed;
      } else {
        clock.time -= elapsed;
        if (clock.time < 0) clock.time = 0;
      }
      stateChanged = true;

      // Handle clock expiration
      if (!isCountUp && clock.time <= 0) {
        _handleClockExpiration(clockName);
      }
    }

    if (stateChanged) {
      _state.notify();
    }
  }

  void _handleClockExpiration(String clockName) {
    switch (clockName) {
      case 'Jam':
        _endJam();
        break;
      case 'Period':
        _endPeriod();
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
    _backgroundedAt = DateTime.now();
    _tickTimer?.cancel();

    // Snapshot clock states
    _backgroundClockSnapshot = {};
    _backgroundRunningSnapshot = {};
    for (final entry in _state.clocks.entries) {
      _backgroundClockSnapshot![entry.key] = entry.value.time;
      _backgroundRunningSnapshot![entry.key] = entry.value.running;
    }
  }

  void _onResumed() {
    if (_backgroundedAt == null || _backgroundClockSnapshot == null) {
      _startTickTimer();
      return;
    }

    final elapsed = DateTime.now().difference(_backgroundedAt!).inMilliseconds;
    _backgroundedAt = null;

    // Reconstruct clock states
    for (final entry in _state.clocks.entries) {
      final clockName = entry.key;
      final clock = entry.value;
      final wasRunning = _backgroundRunningSnapshot?[clockName] ?? false;

      if (!wasRunning) continue;

      final snapshotTime = _backgroundClockSnapshot![clockName]!;
      final isCountUp = clockName == 'Lineup' || clockName == 'Timeout';

      if (isCountUp) {
        clock.time = snapshotTime + elapsed;
      } else {
        clock.time = snapshotTime - elapsed;
        if (clock.time < 0) clock.time = 0;

        // Handle expirations that occurred during background
        if (clock.time <= 0 && snapshotTime > 0) {
          _handleClockExpiration(clockName);
        }
      }
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
    if (_phase == GamePhase.preGame) {
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

    // Stop lineup clock
    _state.clocks['Lineup']!.running = false;

    // Start jam
    _currentJam++;
    _state.clocks['Jam']!.time = ruleset.jamDurationMs;
    _state.clocks['Jam']!.number = _currentJam;
    _state.clocks['Jam']!.running = true;
    _state.clocks['Period']!.running = true;

    _state.inJam = true;
    _phase = GamePhase.jam;

    _state.labelStart = "Start Jam";
    _state.labelStop = "Stop Jam";

    _state.notify();
  }

  @override
  void stopJam() {
    if (_phase == GamePhase.preGame) {
      // "Start Lineup" - begin the period
      _startPeriod(1);
      _startLineup();
      return;
    }

    if (_phase == GamePhase.jam) {
      _endJam();
    } else if (_phase == GamePhase.timeout) {
      endTimeout();
    }
  }

  void _endJam() {
    _state.clocks['Jam']!.running = false;
    _state.inJam = false;

    // Check if period ended
    if (_state.clocks['Period']!.time <= 0) {
      _endPeriod();
      return;
    }

    // Start lineup
    _startLineup();
  }

  void _startLineup() {
    _state.clocks['Lineup']!.time = 0;
    _state.clocks['Lineup']!.running = true;

    _phase = GamePhase.lineup;
    _state.labelStart = "Start Jam";
    _state.labelStop = "Stop Jam";

    _state.notify();
  }

  void _startPeriod(int periodNumber) {
    _currentPeriod = periodNumber;
    _state.clocks['Period']!.number = periodNumber;
    _state.clocks['Period']!.time = ruleset.periodDurationMs;
    _state.clocks['Period']!.displayName = "Period";

    // Reset jam number if ruleset requires it
    if (ruleset.jamsResetPerPeriod && periodNumber > 1) {
      _currentJam = 0;
    }

    // Reset official reviews for new period
    _state.team1.officialReviews = ruleset.reviewsPerPeriod;
    _state.team2.officialReviews = ruleset.reviewsPerPeriod;
    _state.team1.retainedOfficialReview = false;
    _state.team2.retainedOfficialReview = false;

    _phase = GamePhase.lineup;
    _state.notify();
  }

  void _endPeriod() {
    _state.clocks['Jam']!.running = false;
    _state.clocks['Period']!.running = false;
    _state.clocks['Lineup']!.running = false;
    _state.inJam = false;

    if (_currentPeriod >= ruleset.periodCount) {
      // Game over
      _phase = GamePhase.gameOver;
      _state.noMoreJam = true;
      _state.setConnectionStatus("Game Over");
      _state.notify();
      return;
    }

    // Start intermission
    final intermissionDuration =
        ruleset.getIntermissionDurationMs(_currentPeriod);
    _state.clocks['Intermission']!.time = intermissionDuration;
    _state.clocks['Intermission']!.number = _currentPeriod;
    _state.clocks['Intermission']!.running = true;
    _state.clocks['Intermission']!.displayName = "Intermission";

    _phase = GamePhase.intermission;
    _state.notify();
  }

  void _endIntermission() {
    _state.clocks['Intermission']!.running = false;
    _state.clocks['Intermission']!.time = 0;

    // Start next period
    _startPeriod(_currentPeriod + 1);
    _startLineup();
  }

  @override
  void startTimeout() {
    if (_phase == GamePhase.jam) {
      _endJam();
    }

    // Stop lineup clock
    _state.clocks['Lineup']!.running = false;
    _state.clocks['Period']!.running = false;

    // Start timeout clock
    _state.clocks['Timeout']!.time = 0;
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

    // Return to lineup
    _startLineup();
  }

  @override
  void setTimeoutOwner(String owner, {bool isOfficialReview = false}) {
    if (_phase != GamePhase.timeout) {
      // Start timeout first
      startTimeout();
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

    clock.time += deltaMs;
    if (clock.time < 0) clock.time = 0;

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
}

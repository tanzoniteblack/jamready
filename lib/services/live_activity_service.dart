import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/scoreboard_state.dart';

/// Manages the iOS Live Activity showing the period and active secondary clock.
///
/// The right-side "secondary" clock adapts to the current phase:
///   JAM       → Jam clock (countdown, J label)
///   LINEUP    → Lineup clock (countup, L label, inverted alert thresholds)
///   TIMEOUT   → Timeout clock (countup, T label)
///   INTERMISSION → Intermission clock (countdown, I label)
///
/// End/start timestamps are passed so the widget's Text(timerInterval:) can
/// auto-count without app updates while backgrounded.
class LiveActivityService {
  static const _channel = MethodChannel('com.jamready.app/live_activity');

  // MARK: - Public API

  Future<void> startActivity(ScoreboardState state) async {
    if (!Platform.isIOS) return;
    try {
      final id = await _channel.invokeMethod<String?>('startActivity', {
        'team1Name': state.team1.displayName,
        'team2Name': state.team2.displayName,
        ..._stateArgs(state),
      });
      debugPrint('[LiveActivity] started id=$id');
    } on PlatformException catch (e) {
      debugPrint('[LiveActivity] start failed: ${e.message}');
    }
  }

  Future<void> updateActivity(ScoreboardState state) async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('updateActivity', _stateArgs(state));
    } on PlatformException catch (e) {
      debugPrint('[LiveActivity] update failed: ${e.message}');
    }
  }

  Future<void> endActivity() async {
    if (!Platform.isIOS) return;
    try {
      await _channel.invokeMethod('endActivity');
    } on PlatformException catch (e) {
      debugPrint('[LiveActivity] end failed: ${e.message}');
    }
  }

  // MARK: - State Serialisation

  Map<String, dynamic> _stateArgs(ScoreboardState state) {
    final nowS = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final period = state.clocks['Period']!;
    final sec = _secondaryClock(state);

    // For countdown clocks: secTimestamp = now + remaining (end time).
    // For countup clocks:   secTimestamp = now - elapsed  (start time).
    final secTimestamp = sec.clock.running
        ? sec.countsDown
            ? nowS + sec.clock.time / 1000.0
            : nowS - sec.clock.time / 1000.0
        : 0.0;

    return {
      'periodTimeMs':       period.time,
      'periodEndTimestamp': period.running ? nowS + period.time / 1000.0 : 0.0,
      'periodRunning':      period.running,
      'periodNumber':       period.number > 0 ? period.number : 1,

      'secTimeMs':     sec.clock.time,
      'secTimestamp':  secTimestamp,
      'secRunning':    sec.clock.running,
      'secCountsDown': sec.countsDown,
      'secDuration':   _secDuration(state, sec),
      'secLabel':      sec.label,

      'phaseLabel': _phaseLabel(state),
    };
  }

  // MARK: - Secondary Clock Selection

  _SecInfo _secondaryClock(ScoreboardState state) {
    final jam = state.clocks['Jam']!;
    final lineup = state.clocks['Lineup']!;
    final timeout = state.clocks['Timeout']!;
    final intermission = state.clocks['Intermission']!;

    if (jam.running || state.inJam) return _SecInfo(jam, 'J', countsDown: true);
    if (lineup.running && timeout.running) return _SecInfo(lineup, 'L', countsDown: false);
    if (timeout.running) return _SecInfo(timeout, 'T', countsDown: false);
    if (lineup.running) return _SecInfo(lineup, 'L', countsDown: false);
    if (intermission.running && !state.noMoreJam) {
      return _SecInfo(intermission, 'I', countsDown: true);
    }
    return _SecInfo(jam, 'J', countsDown: true);
  }

  // MARK: - Phase Label

  String _phaseLabel(ScoreboardState state) {
    final jam = state.clocks['Jam']!;
    final lineup = state.clocks['Lineup']!;
    final timeout = state.clocks['Timeout']!;
    final intermission = state.clocks['Intermission']!;

    if (jam.running || state.inJam) return 'JAM';
    if (lineup.running && timeout.running) return 'LINEUP';
    if (timeout.running) {
      return state.isOfficialReview ? 'OFFICIAL REVIEW' : 'TIMEOUT';
    }
    if (lineup.running) return 'LINEUP';
    if (intermission.running && !state.noMoreJam) return 'INTERMISSION';
    return 'LINEUP';
  }

  // MARK: - Secondary Clock Duration
  // For countup clocks: the cap used to compute color thresholds in the widget.
  // Countdown clocks return 0 (unused by the widget).

  int _secDuration(ScoreboardState state, _SecInfo sec) {
    if (sec.countsDown) return 0;
    if (sec.label == 'L') {
      return state.inOvertime
          ? state.lineupOvertimeDuration
          : state.lineupDuration;
    }
    // Official timeout is unbounded — 0 tells the widget to skip color warnings.
    // Team timeout cap: amber at 50 s, orange at 55 s, red at 60 s.
    return state.isOfficialReview ? 0 : 60000;
  }
}

class _SecInfo {
  final Clock clock;
  final String label;
  final bool countsDown;
  const _SecInfo(this.clock, this.label, {required this.countsDown});
}

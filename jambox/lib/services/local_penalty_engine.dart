import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/penalty_box_state.dart';
import 'penalty_engine.dart';

/// On-device penalty engine.
/// Drives all timers locally; supports manual jam start/stop for offline use.
class LocalPenaltyEngine extends PenaltyEngine with WidgetsBindingObserver {
  final PenaltyBoxState _state;
  Timer? _ticker;
  DateTime? _lastTick;

  LocalPenaltyEngine(this._state);

  @override
  PenaltyBoxState get state => _state;

  @override
  bool get isLocal => true;

  @override
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    _startTicker();
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _stopTicker();
  }

  void _startTicker() {
    _lastTick = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), _onTick);
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lastTick = null;
  }

  void _onTick(Timer _) {
    final now = DateTime.now();
    final elapsed = _lastTick != null ? now.difference(_lastTick!) : Duration.zero;
    _lastTick = now;
    _state.tick(elapsed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reset tick baseline so we don't jump timers forward on resume
      _lastTick = DateTime.now();
    }
  }

  @override
  void toggleJam() {
    if (_state.jamRunning) {
      _state.onJamEnd();
    } else {
      if (_state.jamRunning == false) {
        _state.jamNumber++;
      }
      _state.onJamStart();
    }
  }

  @override
  void reportPenalty({
    required int teamIndex,
    required String skaterNumber,
    required int periodNumber,
    required int jamNumber,
  }) {
    // No-op in local mode — no CRG to report to
  }
}

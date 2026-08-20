import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/penalty_box_state.dart';
import 'penalty_engine.dart';

/// On-device penalty engine.
/// Drives all timers locally; supports manual jam start/stop for offline use.
class LocalPenaltyEngine extends PenaltyEngine with WidgetsBindingObserver {
  final PenaltyBoxState _state;
  final DateTime Function() _clock;
  Timer? _ticker;
  DateTime? _lastTick;

  LocalPenaltyEngine(this._state, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  @override
  PenaltyBoxState get state => _state;

  @override
  bool get isLocal => true;

  @override
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    await _loadKnownNumbers();
    _state.setKnownNumbersSaveCallback(_saveKnownNumbers);
    _startTicker();
    // Start in jam-running mode so timers are live immediately
    _state.jamNumber = 1;
    _state.onJamStart();
  }

  Future<void> _loadKnownNumbers() async {
    final prefs = await SharedPreferences.getInstance();
    for (final n in prefs.getStringList('jambox_known_t1') ?? []) {
      _state.addKnownNumber(1, n);
    }
    for (final n in prefs.getStringList('jambox_known_t2') ?? []) {
      _state.addKnownNumber(2, n);
    }
  }

  void _saveKnownNumbers() {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setStringList('jambox_known_t1', _state.knownNumbers(1));
      prefs.setStringList('jambox_known_t2', _state.knownNumbers(2));
    });
  }

  @override
  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _stopTicker();
  }

  void _startTicker() {
    _lastTick = _clock();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), _onTick);
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lastTick = null;
  }

  @visibleForTesting
  void startTicker() => _startTicker();

  void _onTick(Timer _) {
    final now = _clock();
    final elapsed = _lastTick != null
        ? now.difference(_lastTick!)
        : Duration.zero;
    _lastTick = now;
    _state.tick(elapsed);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reset tick baseline so we don't jump timers forward on resume
      _lastTick = _clock();
    }
  }

  @override
  void toggleJam() {
    if (_state.jamRunning) {
      _state.onJamEnd();
    } else {
      _state.jamNumber++;
      _state.onJamStart();
    }
  }

  @override
  Future<void> reconnect() async {} // no-op in local mode

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

import 'dart:async';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/penalty_box_state.dart';
import 'penalty_alerts.dart';
import 'penalty_engine.dart';

/// On-device penalty engine.
/// Drives all timers locally; supports manual jam start/stop for offline use.
class LocalPenaltyEngine extends PenaltyEngine with WidgetsBindingObserver {
  final PenaltyBoxState _state;
  Timer? _ticker;

  // Monotonic time source for ticks, so wall-clock changes (e.g. a network
  // time sync) never move running timers.
  Stopwatch _tickStopwatch = clock.stopwatch();
  Duration _lastTickTotal = Duration.zero;

  // Wall-clock time the app was backgrounded. Wall clock is used here because
  // the monotonic clock may not advance while the device sleeps.
  DateTime? _backgroundedAt;

  final PenaltyAlertScheduler? _alerts;
  final bool Function() _jamMayStop;

  /// [alerts] notifies the user of stand and release times while the app is
  /// backgrounded. [jamMayStop] reports whether something outside this app
  /// (CRG) can stop the jam, which makes those times uncertain.
  LocalPenaltyEngine(
    this._state, {
    PenaltyAlertScheduler? alerts,
    bool Function()? jamMayStop,
  }) : _alerts = alerts,
       _jamMayStop = jamMayStop ?? (() => false);

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
    _bestEffort(_alerts?.cancelAll());
  }

  void _startTicker() {
    _ticker?.cancel();
    _tickStopwatch = clock.stopwatch()..start();
    _lastTickTotal = Duration.zero;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _backgroundedAt = null;
  }

  @visibleForTesting
  void startTicker() => _startTicker();

  void _tick() {
    final total = _tickStopwatch.elapsed;
    final elapsed = total - _lastTickTotal;
    _lastTickTotal = total;
    _state.tick(elapsed);
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
    if (_ticker == null || _backgroundedAt != null) return;
    _tick(); // account for time since the last tick
    _ticker!.cancel();
    _backgroundedAt = clock.now();
    _scheduleAlerts();
  }

  /// Penalty time keeps running while the app is backgrounded, so catch the
  /// timers up on the time spent away.
  void _onResumed() {
    if (_backgroundedAt == null) return;
    _catchUp();
    _backgroundedAt = null;
    _bestEffort(_alerts?.cancelAll());
    _startTicker();
  }

  /// Brings running timers up to the current time.
  void _catchUp() {
    final backgroundedAt = _backgroundedAt;
    if (backgroundedAt != null) {
      final now = clock.now();
      final away = now.difference(backgroundedAt);
      if (away > Duration.zero) _state.tick(away);
      _backgroundedAt = now;
    } else if (_ticker != null) {
      _tick();
    }
  }

  /// Applies [change] (such as a jam starting or stopping) at the current
  /// time: timers are caught up first so time since the last tick, or spent
  /// in the background, is counted under the state it was really spent in.
  void applyNow(void Function() change) {
    _catchUp();
    change();
    if (_backgroundedAt != null) _scheduleAlerts();
  }

  void _scheduleAlerts() => _bestEffort(
    _alerts?.schedule(penaltyAlertsFor(_state, jamMayStop: _jamMayStop())),
  );

  /// Alerts are a convenience: a failure to deliver one must not break timing.
  static void _bestEffort(Future<void>? task) =>
      task?.catchError((Object e) => debugPrint('Penalty alert error: $e'));

  @override
  void toggleJam() => applyNow(() {
    if (_state.jamRunning) {
      _state.onJamEnd();
    } else {
      _state.jamNumber++;
      _state.onJamStart();
    }
  });

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

part of '../jam_timer_screen.dart';

extension _JamTimerAlerts on _JamTimerScreenState {
  void _triggerHaptic(int level) {
    if (!_alertsInitialized) {
      // Absorb initial alert state without vibrating so the first real state
      // change after initialization doesn't spuriously trigger haptics.
      if (level > _lastAlertLevel) _lastAlertLevel = level;
      return;
    }
    if (_lastAlertLevel >= level) return;

    _lastAlertLevel = level;
    switch (level) {
      case 1:
        Vibration.vibrate(duration: 400);
        break;
      case 2:
        Vibration.vibrate(
          pattern: [0, 200, 100, 200],
          intensities: [0, 255, 0, 255],
        );
        break;
      case 3:
        Vibration.vibrate(duration: 1000, amplitude: 255);
        break;
    }
  }

  Color _determineAlertColor(ScoreboardState state) {
    Clock? activeClock;
    bool isCountUp = false;
    int duration = 0;

    if (state.inJam) {
      activeClock = state.clocks['Jam'];
      isCountUp = false;
    } else if (state.clocks['Jam']!.time == 0 &&
        !state.clocks['Lineup']!.running &&
        !state.clocks['Timeout']!.running &&
        !state.clocks['Intermission']!.running) {
      activeClock = state.clocks['Jam'];
      isCountUp = false;
    } else if (state.clocks['Lineup']?.running == true) {
      activeClock = state.clocks['Lineup'];
      isCountUp = true;
      duration = state.lineupDuration;
    }

    if (_wasInJam && !state.inJam && state.clocks['Lineup']?.running == true) {
      _triggerHaptic(3);
    }
    _wasInJam = state.inJam;

    _alertsInitialized = true;

    bool allowStopped =
        activeClock != null && activeClock.name == 'Jam' && activeClock.time == 0;

    if (activeClock == null || (!activeClock.running && !allowStopped)) {
      _lastAlertLevel = 0;
      _lastAlertClockName = "";
      if (state.clocks['Intermission']?.running == true) {
        return Colors.orange;
      }
      return _JamTimerScreenState._healthyColor;
    }

    if (_lastAlertClockName != activeClock.name) {
      _lastAlertLevel = 0;
      _lastAlertClockName = activeClock.name;
    }

    final time = activeClock.time;

    if (isCountUp) {
      if (time >= duration) {
        _triggerHaptic(3);
        return Colors.red;
      } else if (time >= duration - 5000) {
        _triggerHaptic(2);
        return Colors.orange.shade800;
      } else if (time >= duration - 10000) {
        _triggerHaptic(1);
        return Colors.amber.shade700;
      }
    } else {
      if (time <= 0) {
        _triggerHaptic(3);
        return Colors.red;
      } else if (time <= 5000) {
        _triggerHaptic(2);
        return Colors.orange.shade800;
      } else if (time <= 10000) {
        _triggerHaptic(1);
        return Colors.amber.shade700;
      }
    }

    bool safe = isCountUp ? (time < duration - 10000) : (time > 10000);
    if (safe) {
      _lastAlertLevel = 0;
      return _JamTimerScreenState._healthyColor;
    }

    if (_lastAlertLevel >= 3) return Colors.red;
    if (_lastAlertLevel >= 2) return Colors.orange.shade800;
    if (_lastAlertLevel >= 1) return Colors.amber.shade700;

    return _JamTimerScreenState._healthyColor;
  }
}

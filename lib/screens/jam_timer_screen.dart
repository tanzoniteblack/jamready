import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scoreboard_state.dart';
import '../services/scoreboard_service.dart';
import '../widgets/team_panel.dart';
import '../widgets/clock_display.dart';
import '../widgets/jam_controls.dart';
import 'package:vibration/vibration.dart';
import 'settings_screen.dart';

class JamTimerScreen extends StatefulWidget {
  const JamTimerScreen({super.key});

  @override
  State<JamTimerScreen> createState() => _JamTimerScreenState();
}

class _JamTimerScreenState extends State<JamTimerScreen> {
  late ScoreboardService _service;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _connectToServer();
    });
  }

  Future<void> _connectToServer() async {
    final state = Provider.of<ScoreboardState>(context, listen: false);
    _service = ScoreboardService(state);

    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('server_host') ?? '10.0.2.2';
    final port = prefs.getString('server_port') ?? '8000';
    final url = "ws://$host:$port";

    _service.connect(url);
  }

  @override
  void dispose() {
    _service.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text(
          "JAM TIMER",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.settings, color: Colors.white70),
          onPressed: () {
            // Navigate to Settings Screen
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            );
          },
        ),
        actions: [
          Consumer<ScoreboardState>(
            builder: (context, state, _) {
              Color statusColor;
              if (state.connectionStatus == "Connected") {
                statusColor = Colors.green;
              } else if (state.connectionStatus.startsWith("Connecting")) {
                statusColor = Colors.orange;
              } else {
                statusColor = Colors.red;
              }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<ScoreboardState>(
        builder: (context, state, _) {
          final isConnected = state.connectionStatus == "Connected";

          return RefreshIndicator(
            onRefresh: () async {
              _service.disconnect();
              await _connectToServer();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Teams
                    Row(
                      children: [
                        Expanded(
                          child: TeamPanel(
                            team: state.team1,
                            isLeft: true,
                            enabled: isConnected,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TeamPanel(
                            team: state.team2,
                            isLeft: false,
                            enabled: isConnected,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Active Clock
                    ClockDisplay(
                      clock: _determineActiveClock(state),
                      textColor: _determineAlertColor(state),
                      enabled: isConnected,
                      onAdjust: (val) {
                        final active = _determineActiveClock(state);
                        _service.send(
                          "Set",
                          "ScoreBoard.CurrentGame.Clock(${active.name}).Time",
                          val,
                          flag: "change",
                        );
                      },
                    ),

                    const SizedBox(height: 48),

                    // Controls
                    JamControls(
                      inJam: state.inJam,
                      isPrePeriod: _isPrePeriod(state),
                      isIntermission:
                          (state.clocks['Intermission']?.running ?? false) ||
                          (state.clocks['Period']?.number == 0),
                      startLabel: state.labelStart,
                      stopLabel: state.labelStop,
                      timeoutLabel: state.labelTimeout,
                      alertColor: _determineAlertColor(state),
                      enabled: isConnected,
                      onStartJam: () => _service.send(
                        "Set",
                        "ScoreBoard.CurrentGame.StartJam",
                        true,
                      ),
                      onStopJam: () => _service.send(
                        "Set",
                        "ScoreBoard.CurrentGame.StopJam",
                        true,
                      ),
                      onTimeout: () => _service.send(
                        "Set",
                        "ScoreBoard.CurrentGame.Timeout",
                        true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Clock _determineActiveClock(ScoreboardState state) {
    if (state.clocks['Timeout']!.running || state.clocks['Timeout']!.time > 0) {
      return state.clocks['Timeout']!;
    }
    if (state.inJam) {
      return state.clocks['Jam']!;
    }
    // Handle 'Jam Ended but Lineup not started' state - Show Jam Clock at 0:00
    if (state.clocks['Jam']!.time == 0 &&
        state.clocks['Jam']!.time !=
            state
                .clocks['Lineup']!
                .time && // Avoid ambiguity if both are 0 at start
        !state.clocks['Lineup']!.running &&
        !state.clocks['Intermission']!.running) {
      return state.clocks['Jam']!;
    }
    if (state.clocks['Lineup']!.running) {
      return state.clocks['Lineup']!;
    }
    if (state.clocks['Intermission']!.running) {
      return state.clocks['Intermission']!;
    }
    return state.clocks['Lineup']!;
  }

  bool _isPrePeriod(ScoreboardState state) {
    if (state.clocks['Period']?.number == 0) return true;
    if (state.clocks['Intermission']?.running == true) return true;

    bool anyClockRunning = state.clocks.values.any((c) => c.running);
    bool inTimeout =
        state.timeoutOwner.isNotEmpty ||
        state.officialReview.isNotEmpty ||
        state.clocks['Timeout']!.running;

    if (!anyClockRunning && !state.inJam && !inTimeout) {
      return true;
    }
    return false;
  }

  // Track last alert state
  int _lastAlertLevel = 0; // 0: None, 1: Low, 2: Warning, 3: High
  String _lastAlertClockName = "";

  Color? _determineAlertColor(ScoreboardState state) {
    // Determine which clock is logically "active" for alerts
    Clock? activeClock;
    bool isCountUp = false;
    int duration = 0;

    if (state.inJam) {
      activeClock = state.clocks['Jam'];
      isCountUp = false; // Jam Clock counts DOWN
    } else if (state.clocks['Jam']!.time == 0 &&
        !state.clocks['Lineup']!.running &&
        !state.clocks['Timeout']!.running &&
        !state.clocks['Intermission']!.running) {
      // Limbo: Jam ended (0:00), Lineup not started. Treat as Jam Clock active (High Alert)
      activeClock = state.clocks['Jam'];
      isCountUp = false;
    } else if (state.clocks['Lineup']?.running == true) {
      activeClock = state.clocks['Lineup'];
      isCountUp = true; // Lineup Clock counts UP
      duration = state.lineupDuration;
    }

    // If no relevant clock is running, reset and return
    // SPECIAL CASE: Allow activeClock to be processed if it's the Jam clock at 0:00 (Limbo state), even if not running.
    bool allowStopped =
        activeClock != null &&
        activeClock.name == 'Jam' &&
        activeClock.time == 0;

    if (activeClock == null || (!activeClock.running && !allowStopped)) {
      _lastAlertLevel = 0;
      _lastAlertClockName = "";
      return null;
    }

    // Reset alert level if we switched clocks
    if (_lastAlertClockName != activeClock.name) {
      _lastAlertLevel = 0;
      _lastAlertClockName = activeClock.name;
    }

    final time = activeClock.time;

    if (isCountUp) {
      // LINEUP LOGIC (Count Up)
      // Alerts at 20s (Low), 25s (Warning), 30s+ (High)

      if (time >= duration) {
        // High Alert (30s elapsed or more)
        if (_lastAlertLevel < 3) {
          Vibration.vibrate(duration: 1000, amplitude: 255);
          _lastAlertLevel = 3;
        }
        return Colors.red;
      } else if (time >= duration - 5000) {
        // >= 25000
        // Warning Alert (25s elapsed)
        if (_lastAlertLevel < 2) {
          Vibration.vibrate(
            pattern: [0, 200, 100, 200],
            intensities: [0, 255, 0, 255],
          );
          _lastAlertLevel = 2;
        }
        return Colors.orange.shade800;
      } else if (time >= duration - 10000) {
        // >= 20000
        // Low Alert (20s elapsed)
        if (_lastAlertLevel < 1) {
          Vibration.vibrate(duration: 400);
          _lastAlertLevel = 1;
        }
        return Colors.amber.shade700;
      }
    } else {
      // JAM LOGIC (Count Down)
      // Alerts at 10s (Low), 5s (Warning), 0s (High)

      if (time <= 0) {
        // High Alert (0s remaining)
        if (_lastAlertLevel < 3) {
          Vibration.vibrate(duration: 1000, amplitude: 255);
          _lastAlertLevel = 3;
        }
        return Colors.red;
      } else if (time <= 5000) {
        // Warning Alert (5s remaining)
        if (_lastAlertLevel < 2) {
          Vibration.vibrate(
            pattern: [0, 200, 100, 200],
            intensities: [0, 255, 0, 255],
          );
          _lastAlertLevel = 2;
        }
        return Colors.orange.shade800;
      } else if (time <= 10000) {
        // Low Alert (10s remaining)
        if (_lastAlertLevel < 1) {
          Vibration.vibrate(duration: 400);
          _lastAlertLevel = 1;
        }
        return Colors.amber.shade700;
      }
    }

    // Reset if we are outside of alert zones
    // For count up: < 20s (duration - 10000)
    // For count down: > 10s
    bool safe = isCountUp ? (time < duration - 10000) : (time > 10000);
    if (safe) {
      _lastAlertLevel = 0;
      // return null not needed if we want to clear color
      return null;
    }

    // If we are in an alert zone but level is already set (or higher), return corresponding color
    if (_lastAlertLevel >= 3) return Colors.red;
    if (_lastAlertLevel >= 2) return Colors.orange.shade800;
    if (_lastAlertLevel >= 1) return Colors.amber.shade700;

    return null;
  }
}

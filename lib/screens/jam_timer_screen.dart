import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:roller_derby_scoreboard_flutter/styles/text_styles.dart';
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
                    const SizedBox(height: 24),

                    // Period / Intermission Clock (top group, like original web)
                    _buildPeriodClockRow(state, isConnected),

                    const SizedBox(height: 24),

                    // Active Game Clock (Jam / Lineup / Timeout)
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

                    const SizedBox(height: 24),

                    // Timeout Type Buttons (visible during timeout, like original web)
                    if (state.labelStop == "End Timeout")
                      _buildTimeoutTypeSection(state, isConnected),

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
    // Original web implementation uses CSS to show only the first running clock
    // in DOM order: Jam, Lineup, Timeout.
    // CSS: [Clock]:not(.Running) { display: none; }
    //      .Running ~ .Running { display: none; }
    // Additionally, Jam clock gets InJam styling when InJam is true.

    // Priority 1: Jam Clock - running OR InJam flag is true
    if (state.clocks['Jam']!.running || state.inJam) {
      return state.clocks['Jam']!;
    }

    // Priority 2: Lineup Clock - running (includes "Post Timeout" state)
    if (state.clocks['Lineup']!.running) {
      return state.clocks['Lineup']!;
    }

    // Priority 3: Timeout Clock - running
    if (state.clocks['Timeout']!.running) {
      return state.clocks['Timeout']!;
    }

    // No Jam/Lineup/Timeout clocks running.
    // Fall through to the Period/Intermission group logic:

    if (state.clocks['Intermission']!.running) {
      return state.clocks['Intermission']!;
    }

    // Default: show Lineup (which will be at 0:00 pre-game)
    return state.clocks['Lineup']!;
  }

  Widget _buildPeriodClockRow(ScoreboardState state, bool isConnected) {
    // Original web: show Intermission when running, otherwise show Period
    final bool showIntermission = state.clocks['Intermission']!.running;
    final clock = showIntermission
        ? state.clocks['Intermission']!
        : state.clocks['Period']!;

    final String label = clock.displayName.isNotEmpty
        ? "${clock.displayName} ${clock.number}"
        : "${clock.name} ${clock.number}";

    final contentColor = isConnected ? Colors.white70 : Colors.white24;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: showIntermission
            ? Colors.orange.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: showIntermission
              ? Colors.orange.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.clockLabel.copyWith(
              color: contentColor,
              fontSize: 14,
            ),
          ),
          Row(
            children: [
              _buildMiniAdjustButton(
                "-",
                isConnected
                    ? () {
                        _service.send(
                          "Set",
                          "ScoreBoard.CurrentGame.Clock(${clock.name}).Time",
                          "-1000",
                          flag: "change",
                        );
                      }
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _formatTime(clock.time),
                  style: AppTextStyles.buttonText.copyWith(
                    color: contentColor,
                    fontSize: 18,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              _buildMiniAdjustButton(
                "+",
                isConnected
                    ? () {
                        _service.send(
                          "Set",
                          "ScoreBoard.CurrentGame.Clock(${clock.name}).Time",
                          "+1000",
                          flag: "change",
                        );
                      }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniAdjustButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: 32,
      height: 32,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(
            color: onPressed != null ? Colors.white24 : Colors.white10,
          ),
          shape: const CircleBorder(),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onPressed != null ? Colors.white60 : Colors.white24,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  String _formatTime(int milliseconds) {
    int seconds = (milliseconds / 1000).ceil();
    int minutes = (seconds / 60).floor();
    int remainingSeconds = (seconds % 60);
    return "${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
  }

  Widget _buildTimeoutTypeSection(ScoreboardState state, bool isConnected) {
    // Determine current timeout owner to highlight the active button.
    final owner = state.timeoutOwner;
    // OfficialReview can be boolean true/false or string "true"/"false"
    final isOr =
        state.officialReview == "true" || state.officialReview == "True";

    // TimeoutOwner is a UUID, match against team serverId
    final bool isTeam1TO =
        owner.isNotEmpty && owner == state.team1.serverId && !isOr;
    final bool isTeam2TO =
        owner.isNotEmpty && owner == state.team2.serverId && !isOr;
    final bool isOfficialTO = owner == "O";
    final bool isTeam1OR =
        owner.isNotEmpty && owner == state.team1.serverId && isOr;
    final bool isTeam2OR =
        owner.isNotEmpty && owner == state.team2.serverId && isOr;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          // Team Row
          Row(
            children: [
              // Team 1 buttons
              Expanded(
                child: Column(
                  children: [
                    Text(
                      state.team1.displayName,
                      style: AppTextStyles.clockLabel.copyWith(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    _buildInlineTimeoutButton(
                      "Timeout",
                      isActive: isTeam1TO,
                      count: state.team1.timeouts,
                      color: Colors.white,
                      enabled: isConnected,
                      onTap: () => _service.send(
                        "Set",
                        "ScoreBoard.CurrentGame.Team(1).Timeout",
                        true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildInlineTimeoutButton(
                      "Review",
                      isActive: isTeam1OR,
                      count: state.team1.officialReviews,
                      color: Colors.blue.shade300,
                      enabled: isConnected,
                      onTap: () => _service.send(
                        "Set",
                        "ScoreBoard.CurrentGame.Team(1).OfficialReview",
                        true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Official Timeout (center)
              Expanded(
                child: _buildInlineTimeoutButton(
                  "Official TO",
                  isActive: isOfficialTO,
                  color: Colors.amber,
                  enabled: isConnected,
                  onTap: () => _service.send(
                    "Set",
                    "ScoreBoard.CurrentGame.OfficialTimeout",
                    true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Team 2 buttons
              Expanded(
                child: Column(
                  children: [
                    Text(
                      state.team2.displayName,
                      style: AppTextStyles.clockLabel.copyWith(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    _buildInlineTimeoutButton(
                      "Timeout",
                      isActive: isTeam2TO,
                      count: state.team2.timeouts,
                      color: Colors.white,
                      enabled: isConnected,
                      onTap: () => _service.send(
                        "Set",
                        "ScoreBoard.CurrentGame.Team(2).Timeout",
                        true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildInlineTimeoutButton(
                      "Review",
                      isActive: isTeam2OR,
                      count: state.team2.officialReviews,
                      color: Colors.blue.shade300,
                      enabled: isConnected,
                      onTap: () => _service.send(
                        "Set",
                        "ScoreBoard.CurrentGame.Team(2).OfficialReview",
                        true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // End Timeout button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: isConnected
                  ? () => _service.send(
                      "Set",
                      "ScoreBoard.CurrentGame.StopJam",
                      true,
                    )
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                disabledBackgroundColor: Colors.grey.shade800,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                "END TIMEOUT",
                style: AppTextStyles.buttonText.copyWith(
                  fontSize: 16,
                  color: isConnected ? Colors.white : Colors.white38,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineTimeoutButton(
    String label, {
    required bool isActive,
    int? count,
    required Color color,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: OutlinedButton(
        onPressed: enabled ? onTap : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          backgroundColor: isActive ? color.withValues(alpha: 0.2) : null,
          side: BorderSide(
            color: isActive ? color : Colors.white24,
            width: isActive ? 2 : 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled
                      ? (isActive ? color : Colors.white70)
                      : Colors.white24,
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 4),
              Text(
                "$count",
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white24,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
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

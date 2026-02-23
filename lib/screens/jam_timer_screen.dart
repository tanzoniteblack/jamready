import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:roller_derby_jam_timer/styles/text_styles.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scoreboard_state.dart';
import '../services/game_engine.dart';
import '../services/remote_game_engine.dart';
import '../widgets/team_panel.dart';
import '../widgets/clock_display.dart';
import '../widgets/jam_controls.dart';
import '../widgets/prominent_period_clock.dart';
import 'package:vibration/vibration.dart';
import 'settings_screen.dart';

class JamTimerScreen extends StatefulWidget {
  /// Optional game engine. If null, creates a RemoteGameEngine.
  final GameEngine? engine;

  const JamTimerScreen({super.key, this.engine});

  @override
  State<JamTimerScreen> createState() => _JamTimerScreenState();
}

class _JamTimerScreenState extends State<JamTimerScreen>
    with WidgetsBindingObserver {
  GameEngine? _engine;
  bool _showUndo = false;
  bool _useReplace = false;

  // "Healthy" color used when clock is in normal state (no alerts)
  static final Color _healthyColor = Colors.green.shade400;

  bool get _isLocalMode => _engine?.isLocal ?? false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.engine != null) {
      _engine = widget.engine;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _engine!.initialize();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _connectToServer();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Only handle lifecycle for remote engine - local engine handles its own
    if (!_isLocalMode && state == AppLifecycleState.resumed) {
      _connectToServer(forceReconnect: true);
    }
  }

  Future<void> _connectToServer({bool forceReconnect = false}) async {
    if (_isLocalMode) return;

    final state = Provider.of<ScoreboardState>(context, listen: false);

    // If already connected, don't create a new service unless forced
    if (_engine != null &&
        _engine is RemoteGameEngine &&
        (_engine as RemoteGameEngine).isConnected &&
        !forceReconnect) {
      return;
    }

    // Clean up existing engine if forcing reconnect
    if (forceReconnect && _engine != null) {
      (_engine as RemoteGameEngine).disconnect();
    }

    final remoteEngine = RemoteGameEngine(state);
    _engine = remoteEngine;

    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('server_host') ?? '10.0.2.2';
    final port = prefs.getString('server_port') ?? '8000';
    final url = "ws://$host:$port";

    remoteEngine.connect(url);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _engine?.dispose();
    super.dispose();
  }

  Future<void> _navigateToHome(BuildContext context) async {
    if (_isLocalMode) {
      // Show confirmation dialog for local games
      final shouldExit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'End Game?',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'Leaving will end the current game. This cannot be undone.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('END GAME'),
            ),
          ],
        ),
      );

      if (shouldExit != true) return;
    }

    // Clean up current engine before navigating
    _engine?.dispose();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const SettingsScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: Consumer<ScoreboardState>(
          builder: (context, state, _) {
            return Text(
              "JAM TIMER",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _determineAlertColor(state),
              ),
            );
          },
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            _isLocalMode ? Icons.home : Icons.settings,
            color: Colors.white70,
          ),
          onPressed: () => _navigateToHome(context),
        ),
        actions: [
          Consumer<ScoreboardState>(
            builder: (context, state, _) {
              if (_isLocalMode) {
                // Show "LOCAL" badge for offline mode
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.orange,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.phonelink_off,
                            color: Colors.orange,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'LOCAL',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              // Remote mode - show connection status dot
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
          final isEnabled = _isLocalMode ||
              state.connectionStatus == "Connected";

          return RefreshIndicator(
            onRefresh: () async {
              if (!_isLocalMode) {
                await _connectToServer(forceReconnect: true);
              }
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
                            enabled: isEnabled,
                            onRetainedToggle: (val) =>
                                _engine?.setRetainedReview(1, val),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TeamPanel(
                            team: state.team2,
                            isLeft: false,
                            enabled: isEnabled,
                            onRetainedToggle: (val) =>
                                _engine?.setRetainedReview(2, val),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Period / Intermission Clock
                    // In local mode, show prominent period clock
                    // In remote mode, show period clock row (unless intermission)
                    if (_isLocalMode)
                      _buildLocalModePeriodClock(state, isEnabled)
                    else if (!(state.clocks['Intermission']?.running ?? false))
                      _buildPeriodClockRow(state, isEnabled),

                    if (_isLocalMode ||
                        !(state.clocks['Intermission']?.running ?? false))
                      const SizedBox(height: 24),

                    // Active Game Clock (Jam / Lineup / Timeout) or Ready indicator
                    if (_isReadyToStart(state))
                      _buildReadyToStartDisplay(state, isEnabled)
                    else
                      ClockDisplay(
                        clock: _determineActiveClock(state),
                        textColor: _determineAlertColor(state),
                        enabled: isEnabled,
                        onAdjust: (val) {
                          final active = _determineActiveClock(state);
                          final delta = int.tryParse(val) ?? 0;
                          _engine?.adjustClock(active.name, delta);
                        },
                      ),

                    const SizedBox(height: 24),

                    // Timeout Type Buttons (visible during timeout) OR normal controls
                    if (state.labelStop == "End Timeout")
                      _buildTimeoutTypeSection(state, isEnabled)
                    else
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
                        enabled: isEnabled,
                        onStartJam: () => _engine?.startJam(),
                        onStopJam: () => _engine?.stopJam(),
                        onTimeout: () => _engine?.startTimeout(),
                      ),

                    // Undo / Replace Section (only for remote mode)
                    if (!_isLocalMode && state.labelUndo != "No Action")
                      _buildUndoSection(state, isEnabled),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocalModePeriodClock(ScoreboardState state, bool isEnabled) {
    final bool showIntermission = state.clocks['Intermission']!.running;
    final clock = showIntermission
        ? state.clocks['Intermission']!
        : state.clocks['Period']!;

    return ProminentPeriodClock(
      clock: clock,
      enabled: isEnabled,
      onAdjust: (delta) => _engine?.adjustClock(clock.name, delta),
    );
  }

  Clock _determineActiveClock(ScoreboardState state) {
    // Priority 1: Jam Clock - running OR InJam flag is true
    if (state.clocks['Jam']!.running || state.inJam) {
      return state.clocks['Jam']!;
    }

    // Priority 2: Lineup Clock - running
    if (state.clocks['Lineup']!.running) {
      return state.clocks['Lineup']!;
    }

    // Priority 3: Timeout Clock - running
    if (state.clocks['Timeout']!.running) {
      return state.clocks['Timeout']!;
    }

    // Fall through to Period/Intermission
    if (state.clocks['Intermission']!.running) {
      return state.clocks['Intermission']!;
    }

    // Default: show Lineup
    return state.clocks['Lineup']!;
  }

  Widget _buildPeriodClockRow(ScoreboardState state, bool isEnabled) {
    final bool showIntermission = state.clocks['Intermission']!.running;
    final clock = showIntermission
        ? state.clocks['Intermission']!
        : state.clocks['Period']!;

    final String label = clock.displayName.isNotEmpty
        ? "${clock.displayName} ${clock.number}"
        : "${clock.name} ${clock.number}";

    final contentColor = isEnabled ? Colors.white70 : Colors.white24;

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
                isEnabled
                    ? () => _engine?.adjustClock(clock.name, -1000)
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
                isEnabled
                    ? () => _engine?.adjustClock(clock.name, 1000)
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

  Widget _buildTimeoutTypeSection(ScoreboardState state, bool isEnabled) {
    final owner = state.timeoutOwner;
    final isOr =
        state.officialReview == "true" || state.officialReview == "True";

    // For local mode, owner is '1' or '2', for remote it's a UUID
    final bool isTeam1TO = _isLocalMode
        ? (owner == '1' && !isOr)
        : (owner.isNotEmpty && owner == state.team1.serverId && !isOr);
    final bool isTeam2TO = _isLocalMode
        ? (owner == '2' && !isOr)
        : (owner.isNotEmpty && owner == state.team2.serverId && !isOr);
    final bool isOfficialTO = owner == "O";
    final bool isTeam1OR = _isLocalMode
        ? (owner == '1' && isOr)
        : (owner.isNotEmpty && owner == state.team1.serverId && isOr);
    final bool isTeam2OR = _isLocalMode
        ? (owner == '2' && isOr)
        : (owner.isNotEmpty && owner == state.team2.serverId && isOr);

    return Column(
      children: [
        // Official Timeout button
        _buildTimeoutButton(
          "OFFICIAL TIMEOUT",
          isActive: isOfficialTO,
          color: Colors.amber,
          enabled: isEnabled,
          height: 56,
          onTap: () => _engine?.setTimeoutOwner('O'),
        ),

        const SizedBox(height: 16),

        // Team timeout/review rows
        Row(
          children: [
            // Team 1 column
            Expanded(
              child: Column(
                children: [
                  Text(
                    state.team1.displayName,
                    style: AppTextStyles.clockLabel.copyWith(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  _buildTimeoutButton(
                    "TIMEOUT",
                    isActive: isTeam1TO,
                    count: state.team1.timeouts,
                    color: Colors.white,
                    enabled: isEnabled,
                    height: 48,
                    onTap: () => _engine?.setTimeoutOwner('1'),
                  ),
                  const SizedBox(height: 8),
                  _buildTimeoutButton(
                    "REVIEW",
                    isActive: isTeam1OR,
                    count: state.team1.officialReviews,
                    color: Colors.blue.shade300,
                    enabled: isEnabled,
                    height: 48,
                    onTap: () =>
                        _engine?.setTimeoutOwner('1', isOfficialReview: true),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Team 2 column
            Expanded(
              child: Column(
                children: [
                  Text(
                    state.team2.displayName,
                    style: AppTextStyles.clockLabel.copyWith(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  _buildTimeoutButton(
                    "TIMEOUT",
                    isActive: isTeam2TO,
                    count: state.team2.timeouts,
                    color: Colors.white,
                    enabled: isEnabled,
                    height: 48,
                    onTap: () => _engine?.setTimeoutOwner('2'),
                  ),
                  const SizedBox(height: 8),
                  _buildTimeoutButton(
                    "REVIEW",
                    isActive: isTeam2OR,
                    count: state.team2.officialReviews,
                    color: Colors.blue.shade300,
                    enabled: isEnabled,
                    height: 48,
                    onTap: () =>
                        _engine?.setTimeoutOwner('2', isOfficialReview: true),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // End Timeout button
        _buildEndTimeoutButton(isEnabled),
      ],
    );
  }

  Widget _buildTimeoutButton(
    String label, {
    required bool isActive,
    int? count,
    required Color color,
    required bool enabled,
    required double height,
    required VoidCallback onTap,
  }) {
    final bool useDarkText = isActive &&
        (color == Colors.amber || color.computeLuminance() > 0.5);
    final textColor = useDarkText ? Colors.black87 : Colors.white;

    final highlightColor = Color.lerp(color, Colors.white, 0.08)!;
    final shadowColor = Color.lerp(color, Colors.black, 0.12)!;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: enabled && isActive
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                gradient: isActive && enabled
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [highlightColor, color, shadowColor],
                        stops: const [0.0, 0.5, 1.0],
                      )
                    : null,
                color: isActive ? null : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isActive ? color : Colors.white30,
                  width: isActive ? 2 : 1,
                ),
              ),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: enabled
                              ? (isActive ? textColor : Colors.white)
                              : Colors.white38,
                          fontSize: 14,
                          fontWeight:
                              isActive ? FontWeight.bold : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (count != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive
                              ? (useDarkText
                                  ? Colors.black.withValues(alpha: 0.15)
                                  : Colors.black.withValues(alpha: 0.2))
                              : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "$count",
                          style: TextStyle(
                            color: enabled
                                ? (isActive ? textColor : Colors.white)
                                : Colors.white38,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEndTimeoutButton(bool isEnabled) {
    final color = Colors.red.shade700;
    final highlightColor = Color.lerp(color, Colors.white, 0.1)!;
    final shadowColor = Color.lerp(color, Colors.black, 0.15)!;

    return SizedBox(
      width: double.infinity,
      height: 72,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isEnabled ? () => _engine?.endTimeout() : null,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                gradient: isEnabled
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [highlightColor, color, shadowColor],
                        stops: const [0.0, 0.5, 1.0],
                      )
                    : null,
                color: isEnabled ? null : Colors.grey.shade800,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Container(
                alignment: Alignment.center,
                child: Text(
                  "END TIMEOUT",
                  style: AppTextStyles.buttonText.copyWith(
                    fontSize: 24,
                    color: isEnabled ? Colors.white : Colors.white38,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isReadyToStart(ScoreboardState state) {
    final intermission = state.clocks['Intermission'];
    final lineup = state.clocks['Lineup'];
    final period = state.clocks['Period'];

    if (lineup == null || lineup.running) return false;
    if (period == null || period.running) return false;

    // Pre-game: Period 0
    if (period.number == 0 && !lineup.running) {
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

  bool _isPrePeriod(ScoreboardState state) {
    if (state.clocks['Period']?.number == 0) return true;
    if (state.clocks['Intermission']?.running == true) return true;
    if (_isReadyToStart(state)) return true;

    bool anyClockRunning = state.clocks.values.any((c) => c.running);
    bool inTimeout = state.clocks['Timeout']!.running;

    if (!anyClockRunning && !state.inJam && !inTimeout) {
      return true;
    }
    return false;
  }

  Widget _buildReadyToStartDisplay(ScoreboardState state, bool isEnabled) {
    final periodNumber = (state.clocks['Period']?.number ?? 1);
    final color = isEnabled ? _healthyColor : Colors.white12;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: _healthyColor.withValues(alpha: 0.05),
        boxShadow: [
          BoxShadow(
            color: _healthyColor.withValues(alpha: 0.15),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            periodNumber == 0 ? "GAME" : "PERIOD $periodNumber",
            style: AppTextStyles.clockLabel.copyWith(
              fontSize: 22,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              "READY",
              style: AppTextStyles.clockTime.copyWith(color: color),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildUndoSection(ScoreboardState state, bool isEnabled) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "UNDO CONTROLS",
                    style: AppTextStyles.clockLabel.copyWith(
                      fontSize: 11,
                      color: Colors.white38,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                SizedBox(
                  height: 28,
                  child: Switch(
                    value: _showUndo,
                    onChanged: (val) => setState(() => _showUndo = val),
                    activeThumbColor: Colors.amber,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            if (_showUndo) ...[
              const SizedBox(height: 12),
              if (state.labelReplaced.isNotEmpty &&
                  state.labelReplaced != "Replaced")
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Replace "${state.labelReplaced}" with',
                    style: AppTextStyles.clockLabel.copyWith(
                      fontSize: 11,
                      color: Colors.white54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              Row(
                children: [
                  Text(
                    "Use Replace on Undo",
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 28,
                    child: Switch(
                      value: _useReplace,
                      onChanged: (val) => setState(() => _useReplace = val),
                      activeThumbColor: Colors.orange,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: isEnabled
                      ? () {
                          final engine = _engine as RemoteGameEngine;
                          engine.send(
                            "Set",
                            _useReplace
                                ? "ScoreBoard.CurrentGame.ClockReplace"
                                : "ScoreBoard.CurrentGame.ClockUndo",
                            true,
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _useReplace
                        ? Colors.orange.shade800
                        : Colors.grey.shade800,
                    disabledBackgroundColor: Colors.grey.shade900,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    _useReplace
                        ? "REPLACE: ${state.labelUndo}"
                        : state.labelUndo.toUpperCase(),
                    style: AppTextStyles.buttonText.copyWith(
                      fontSize: 15,
                      color: isEnabled ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Track last alert state
  int _lastAlertLevel = 0;
  String _lastAlertClockName = "";
  bool _wasInJam = false;
  bool _alertsInitialized = false;

  void _triggerHaptic(int level) {
    if (!_alertsInitialized) return;
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
        activeClock != null &&
        activeClock.name == 'Jam' &&
        activeClock.time == 0;

    if (activeClock == null || (!activeClock.running && !allowStopped)) {
      _lastAlertLevel = 0;
      _lastAlertClockName = "";
      return _healthyColor;
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
      return _healthyColor;
    }

    if (_lastAlertLevel >= 3) return Colors.red;
    if (_lastAlertLevel >= 2) return Colors.orange.shade800;
    if (_lastAlertLevel >= 1) return Colors.amber.shade700;

    return _healthyColor;
  }
}

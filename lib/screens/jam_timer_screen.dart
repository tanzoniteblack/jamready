import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jam_ready/styles/text_styles.dart';
import 'package:jam_ready/styles/background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

import '../models/scoreboard_state.dart';
import '../services/game_engine.dart';
import '../services/live_activity_service.dart';
import '../services/remote_game_engine.dart';
import '../widgets/clock_display.dart';
import '../widgets/jam_controls.dart';
import '../widgets/prominent_period_clock.dart';
import '../widgets/swipe_button.dart';
import '../widgets/team_panel.dart';
import 'home_screen.dart';

part 'jam_timer/jam_timer_layout.dart';
part 'jam_timer/jam_timer_controls.dart';
part 'jam_timer/jam_timer_logic.dart';
part 'jam_timer/jam_timer_alerts.dart';

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
  final _liveActivity = LiveActivityService();
  ScoreboardState? _scoreboardState;

  // "Healthy" color used when clock is in normal state (no alerts)
  static final Color _healthyColor = Colors.green.shade400;

  bool get _isLocalMode => _engine?.isLocal ?? false;

  // Track last alert state
  int _lastAlertLevel = 0;
  String _lastAlertClockName = "";
  bool _wasInJam = false;
  bool _alertsInitialized = false;
  final Set<int> _timeoutThresholdsTriggered = <int>{};
  String _lastTimeoutAlertOwnerKey = "";

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scoreboardState = Provider.of<ScoreboardState>(context, listen: false);
      _liveActivity.startActivity(_scoreboardState!);
      _scoreboardState!.addListener(_onStateChangedForLiveActivity);
    });
  }

  void _onStateChangedForLiveActivity() {
    if (_scoreboardState != null) {
      _liveActivity.updateActivity(_scoreboardState!);
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
    _scoreboardState?.removeListener(_onStateChangedForLiveActivity);
    _liveActivity.endActivity();
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
          title: const Text('End Game?', style: TextStyle(color: Colors.white)),
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
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('END GAME'),
            ),
          ],
        ),
      );

      if (shouldExit != true) return;
    }

    // Clean up current engine before navigating
    _engine?.dispose();
    if (context.mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScoreboardState>(
      builder: (context, state, _) {
        final alertColor = _determineAlertColor(state);
        final isEnabled = _isLocalMode || state.isConnected;

        return DynamicBackground(
          accentColor: alertColor,
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _buildAppBar(context, state, alertColor),
            body: _buildBody(state, isEnabled, alertColor),
          ),
        );
      },
    );
  }
}

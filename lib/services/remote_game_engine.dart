import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' hide log;
import 'package:logger/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/scoreboard_state.dart';
import 'game_engine.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

/// Allows parsing longer strings than the default console limit
class LongStringOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    log(event.lines.join('\n'));
  }
}

final _log = Logger(
  printer: PrettyPrinter(methodCount: 0, printEmojis: false, colors: true),
  output: LongStringOutput(),
);

/// Remote game engine that connects to a CRG Scoreboard server via WebSocket.
class RemoteGameEngine implements GameEngine {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  final ScoreboardState _state;
  final WebSocketChannelFactory _channelFactory;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _manualDisconnect = false;
  int _reconnectAttempts = 0;
  String? _lastUrl;
  final Random _random = Random();

  RemoteGameEngine(
    this._state, {
    WebSocketChannelFactory? channelFactory,
  }) : _channelFactory = channelFactory ?? WebSocketChannel.connect;

  @override
  bool get isActive => _isConnected;

  @override
  ScoreboardState get state => _state;

  @override
  bool get supportsUndo => true;

  @override
  bool get isLocal => false;

  bool get isConnected => _isConnected;

  @override
  Future<void> initialize() async {
    // Remote engine is initialized via connect()
  }

  Future<void> connect(String url) async {
    if (_isConnected || _isConnecting) return;
    _manualDisconnect = false;
    _lastUrl = url;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    try {
      _isConnecting = true;
      _state.setConnectionStatus("Connecting...");

      final uri = Uri.parse(url);
      final wsUrl = uri.replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws',
        path: '/WS/',
        queryParameters: {'source': 'companion', 'platform': 'mobile'},
      );

      _channel = _channelFactory(wsUrl);
      await _channel!.ready;

      if (_manualDisconnect) {
        _closeChannel();
        _disconnectCleanup();
        return;
      }

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _state.setConnectionStatus("Connected");

      WakelockPlus.enable();

      _channel!.stream.listen(
        (message) {
          _handleMessage(message);
        },
        onDone: () {
          _log.i("Connection closed");
          _disconnectCleanup();
          _scheduleReconnect();
        },
        onError: (error) {
          _log.e("Connection error: $error");
          _disconnectCleanup(error: error.toString());
          _scheduleReconnect();
        },
      );

      _registerPaths();
      _startHeartbeat();
    } catch (e) {
      _isConnecting = false;
      _disconnectCleanup(error: e.toString());
      _scheduleReconnect();
    }
  }

  void _registerPaths() {
    if (!_isConnected) return;

    final paths = [
      "ScoreBoard.CurrentGame.Game",
      "ScoreBoard.CurrentGame.Clock(Period).Time",
      "ScoreBoard.CurrentGame.Clock(Period).Running",
      "ScoreBoard.CurrentGame.Clock(Period).Name",
      "ScoreBoard.CurrentGame.Clock(Period).Number",
      "ScoreBoard.CurrentGame.Clock(Jam).Time",
      "ScoreBoard.CurrentGame.Clock(Jam).Running",
      "ScoreBoard.CurrentGame.Clock(Jam).Number",
      "ScoreBoard.CurrentGame.Clock(Jam).Name",
      "ScoreBoard.CurrentGame.Clock(Lineup).Time",
      "ScoreBoard.CurrentGame.Clock(Lineup).Running",
      "ScoreBoard.CurrentGame.Clock(Lineup).Name",
      "ScoreBoard.CurrentGame.Clock(Lineup).Number",
      "ScoreBoard.CurrentGame.Rule(Lineup.Duration)",
      "ScoreBoard.CurrentGame.Rule(Lineup.OvertimeDuration)",
      "ScoreBoard.CurrentGame.Clock(Timeout).Time",
      "ScoreBoard.CurrentGame.Clock(Timeout).Running",
      "ScoreBoard.CurrentGame.Clock(Timeout).Name",
      "ScoreBoard.CurrentGame.Clock(Intermission).Time",
      "ScoreBoard.CurrentGame.Clock(Intermission).Running",
      "ScoreBoard.CurrentGame.Clock(Intermission).Name",
      "ScoreBoard.CurrentGame.Clock(Intermission).Number",
      "ScoreBoard.CurrentGame.InJam",
      "ScoreBoard.CurrentGame.NoMoreJam",
      "ScoreBoard.CurrentGame.InOvertime",
      "ScoreBoard.CurrentGame.TimeoutOwner",
      "ScoreBoard.CurrentGame.OfficialReview",
      "ScoreBoard.CurrentGame.InjuryContinuationUpcoming",
      "ScoreBoard.CurrentGame.Rule(Jam.InjuryContinuation)",
      "ScoreBoard.CurrentGame.Team(1).Name",
      "ScoreBoard.CurrentGame.Team(1).AlternateName(Operator)",
      "ScoreBoard.CurrentGame.Team(1).UniformColor",
      "ScoreBoard.CurrentGame.Team(1).Color(operator.fg)",
      "ScoreBoard.CurrentGame.Team(1).Color(operator.bg)",
      "ScoreBoard.CurrentGame.Team(1).Score",
      "ScoreBoard.CurrentGame.Team(1).Timeouts",
      "ScoreBoard.CurrentGame.Team(1).OfficialReviews",
      "ScoreBoard.CurrentGame.Team(1).RetainedOfficialReview",
      "ScoreBoard.CurrentGame.Team(1).Id",
      "ScoreBoard.CurrentGame.Team(1).Injury",
      "ScoreBoard.CurrentGame.Team(2).Name",
      "ScoreBoard.CurrentGame.Team(2).AlternateName(Operator)",
      "ScoreBoard.CurrentGame.Team(2).UniformColor",
      "ScoreBoard.CurrentGame.Team(2).Color(operator.fg)",
      "ScoreBoard.CurrentGame.Team(2).Color(operator.bg)",
      "ScoreBoard.CurrentGame.Team(2).Score",
      "ScoreBoard.CurrentGame.Team(2).Timeouts",
      "ScoreBoard.CurrentGame.Team(2).OfficialReviews",
      "ScoreBoard.CurrentGame.Team(2).RetainedOfficialReview",
      "ScoreBoard.CurrentGame.Team(2).Id",
      "ScoreBoard.CurrentGame.Team(2).Injury",
      "ScoreBoard.CurrentGame.Label(Start)",
      "ScoreBoard.CurrentGame.Label(Stop)",
      "ScoreBoard.CurrentGame.Label(Timeout)",
      "ScoreBoard.CurrentGame.Label(Undo)",
      "ScoreBoard.CurrentGame.Label(Replaced)",
      "ScoreBoard.CurrentGame.Rule(Period.Number)",
      "ScoreBoard.CurrentGame.OfficialScore",
    ];

    _log.d("Registering paths");
    final message = {"action": "Register", "paths": paths};
    _channel?.sink.add(jsonEncode(message));
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeChannel();
    _disconnectCleanup();
  }

  @override
  Future<void> dispose() async {
    disconnect();
  }

  void _closeChannel({int? code}) {
    try {
      _channel?.sink.close(code ?? status.normalClosure);
    } on ArgumentError {
      _channel?.sink.close();
    }
  }

  void _disconnectCleanup({String? error}) {
    _isConnected = false;
    _isConnecting = false;
    _heartbeatTimer?.cancel();
    _channel = null;
    _state.setConnectionStatus(
      error != null ? "Error: $error" : "Disconnected",
    );

    WakelockPlus.disable();
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _lastUrl == null) return;
    if (_reconnectTimer != null || _isConnected || _isConnecting) return;

    final baseDelaySeconds = 1 << _reconnectAttempts;
    final cappedSeconds = baseDelaySeconds > 30 ? 30 : baseDelaySeconds;
    final jitterMs = _random.nextInt(500);
    final delay =
        Duration(seconds: cappedSeconds) + Duration(milliseconds: jitterMs);

    _reconnectAttempts += 1;
    _state.setConnectionStatus(
      "Reconnecting in ${delay.inSeconds}s...",
    );

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_manualDisconnect || _lastUrl == null) return;
      connect(_lastUrl!);
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({"action": "Ping"}));
      }
    });
  }

  void _handleMessage(dynamic message) {
    _log.d("Received message: $message");

    if (!_isConnected) {
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _state.setConnectionStatus("Connected");
      WakelockPlus.enable();
    }

    try {
      final decoded = jsonDecode(message);
      if (decoded is Map<String, dynamic>) {
        if (decoded.containsKey('state')) {
          _state.updateFromMap(decoded['state']);
        } else if (decoded.containsKey('updates')) {
          _state.updateFromMap(decoded['updates']);
        } else if (decoded.containsKey('data') &&
            decoded['data'] is Map &&
            decoded['data'].containsKey('state')) {
          _state.updateFromMap(decoded['data']['state']);
        } else {
          _state.updateFromMap(decoded);
        }
      }
    } catch (e) {
      _log.e("Error parsing message: $e");
    }
  }

  void send(String action, String key, dynamic value, {String flag = ""}) {
    if (!_isConnected) {
      _log.w("Not connected to server");
      return;
    }

    final message = jsonEncode({
      "action": action,
      "key": key,
      "value": value,
      "flag": flag,
    });

    _log.d("Sending message: $message");

    _channel?.sink.add(message);
  }

  // GameEngine implementation

  @override
  void startJam() {
    send("Set", "ScoreBoard.CurrentGame.StartJam", true);
  }

  @override
  void stopJam() {
    send("Set", "ScoreBoard.CurrentGame.StopJam", true);
  }

  @override
  void startTimeout() {
    send("Set", "ScoreBoard.CurrentGame.Timeout", true);
  }

  @override
  void endTimeout() {
    send("Set", "ScoreBoard.CurrentGame.StopJam", true);
  }

  @override
  void setTimeoutOwner(String owner, {bool isOfficialReview = false}) {
    if (owner == 'O') {
      send("Set", "ScoreBoard.CurrentGame.OfficialTimeout", true);
    } else if (owner == '1') {
      if (isOfficialReview) {
        send("Set", "ScoreBoard.CurrentGame.Team(1).OfficialReview", true);
      } else {
        send("Set", "ScoreBoard.CurrentGame.Team(1).Timeout", true);
      }
    } else if (owner == '2') {
      if (isOfficialReview) {
        send("Set", "ScoreBoard.CurrentGame.Team(2).OfficialReview", true);
      } else {
        send("Set", "ScoreBoard.CurrentGame.Team(2).Timeout", true);
      }
    }
  }

  @override
  void adjustClock(String clockName, int deltaMs) {
    final value = deltaMs > 0 ? "+$deltaMs" : "$deltaMs";
    send(
      "Set",
      "ScoreBoard.CurrentGame.Clock($clockName).Time",
      value,
      flag: "change",
    );
  }

  @override
  void setClockTime(String clockName, int timeMs) {
    send(
      "Set",
      "ScoreBoard.CurrentGame.Clock($clockName).Time",
      timeMs.toString(),
    );
  }

  @override
  void adjustScore(int teamNumber, int delta) {
    // Remote engine doesn't support direct score adjustment
    // Score is managed by the server
    _log.w("Score adjustment not supported in remote mode");
  }

  @override
  void setRetainedReview(int teamNumber, bool retained) {
    send(
      "Set",
      "ScoreBoard.CurrentGame.Team($teamNumber).RetainedOfficialReview",
      retained,
    );
  }

  @override
  void undo() {
    send("Set", "ScoreBoard.CurrentGame.ClockUndo", true);
  }

  @override
  void endGame() {
    // CRG manages overtime and game-end decisions server-side; no-op here.
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/scoreboard_state.dart';

class ScoreboardService {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  final ScoreboardState _state;
  bool _isConnected = false;

  ScoreboardService(this._state);

  bool get isConnected => _isConnected;

  Future<void> connect(String url) async {
    if (_isConnected) return;

    try {
      _state.setConnectionStatus("Connecting...");

      // Ensure URL is valid
      final uri = Uri.parse(url);
      final wsUrl = uri.replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws',
        path: '/WS/',
        queryParameters: {'source': 'companion', 'platform': 'mobile'},
      );

      _channel = WebSocketChannel.connect(wsUrl);

      // Wait for connection to be established
      await _channel!.ready;

      _isConnected = true;
      _state.setConnectionStatus("Connected");

      _channel!.stream.listen(
            (message) {
          _handleMessage(message);
        },
        onDone: () {
          print("Connection closed");
          _disconnectCleanup();
        },
        onError: (error) {
          print("Connection error: $error");
          _disconnectCleanup(error: error.toString());
        },
      );

      _registerPaths();
      _startHeartbeat();
    } catch (e) {
      // Catch initial connection errors (e.g. Connection Refused)
      _disconnectCleanup(error: e.toString());
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
    ];

    print("Registering paths");
    final message = {"action": "Register", "paths": paths};
    _channel?.sink.add(jsonEncode(message));
  }

  void disconnect() {
    _channel?.sink.close(status.goingAway);
    _disconnectCleanup();
  }

  void _disconnectCleanup({String? error}) {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _channel = null;
    _state.setConnectionStatus(
      error != null ? "Error: $error" : "Disconnected",
    );
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
    print("Received message: $message");
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
          // Fallback for direct key-value pairs or other formats
          _state.updateFromMap(decoded);
        }
      }
    } catch (e) {
      print("Error parsing message: $e");
    }
  }

  void send(String action, String key, dynamic value, {String flag = ""}) {
    if (!_isConnected) {
      print("Not connected to server");
      return;
    }

    print("Sending message: $action $key $value $flag");

    final message = {
      "action": action,
      "key": key,
      "value": value,
      "flag": flag,
    };
    _channel?.sink.add(jsonEncode(message));
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:math' hide log;
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/penalty_box_state.dart';
import 'penalty_engine.dart';
import 'local_penalty_engine.dart';

class _LongStringOutput extends LogOutput {
  @override
  void output(OutputEvent event) => log(event.lines.join('\n'));
}

final _log = Logger(
  printer: PrettyPrinter(methodCount: 0, printEmojis: false, colors: true),
  output: _LongStringOutput(),
);

/// Remote penalty engine that connects to CRG Scoreboard via WebSocket.
/// Subscribes to jam clock and roster paths, reports penalties via Penalty command.
/// Also drives on-device timers (via embedded LocalPenaltyEngine).
class RemotePenaltyEngine extends PenaltyEngine with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  final PenaltyBoxState _state;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _manualDisconnect = false;
  int _reconnectAttempts = 0;
  String? _lastUrl;
  final Random _random = Random();
  late final LocalPenaltyEngine _localEngine;

  RemotePenaltyEngine(this._state) {
    _localEngine = LocalPenaltyEngine(_state);
  }

  @override
  PenaltyBoxState get state => _state;

  @override
  bool get isLocal => false;

  @override
  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    await _localEngine.initialize();
  }

  Future<void> connect(String url) async {
    if (_isConnected || _isConnecting) return;
    _manualDisconnect = false;
    _lastUrl = url;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await initialize();

    try {
      _isConnecting = true;
      _state.setConnectionStatus(ConnectionStatus.connecting, message: 'Connecting...');

      final uri = Uri.parse(url);
      final wsUrl = uri.replace(
        scheme: uri.scheme == 'https' ? 'wss' : 'ws',
        path: '/WS/',
        queryParameters: {'source': 'pbm', 'platform': 'mobile'},
      );

      _channel = WebSocketChannel.connect(wsUrl);
      await _channel!.ready;

      if (_manualDisconnect) {
        _closeChannel();
        _disconnectCleanup();
        return;
      }

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _state.setConnectionStatus(ConnectionStatus.connected, message: 'Connected');
      WakelockPlus.enable();

      _channel!.stream.listen(
        _handleMessage,
        onDone: () {
          _log.i('WebSocket closed');
          _disconnectCleanup();
          _scheduleReconnect();
        },
        onError: (error) {
          _log.e('WebSocket error: $error');
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
      // Jam clock
      'ScoreBoard.CurrentGame.Clock(Jam).Running',
      'ScoreBoard.CurrentGame.Clock(Jam).Number',
      // Period clock
      'ScoreBoard.CurrentGame.Clock(Period).Number',
      // In-jam flag (more reliable than clock running for jam state)
      'ScoreBoard.CurrentGame.InJam',
      // Team names and colors
      'ScoreBoard.CurrentGame.Team(1).Name',
      'ScoreBoard.CurrentGame.Team(1).Color(operator.fg)',
      'ScoreBoard.CurrentGame.Team(1).Color(operator.bg)',
      'ScoreBoard.CurrentGame.Team(2).Name',
      'ScoreBoard.CurrentGame.Team(2).Color(operator.fg)',
      'ScoreBoard.CurrentGame.Team(2).Color(operator.bg)',
      // Roster (mainline CRG path)
      'Game.Team(1).Skater',
      'Game.Team(2).Skater',
      // Roster (alternate path used in some versions)
      'ScoreBoard.CurrentGame.Team(1).Skater(*).Number',
      'ScoreBoard.CurrentGame.Team(1).Skater(*).Name',
      'ScoreBoard.CurrentGame.Team(2).Skater(*).Number',
      'ScoreBoard.CurrentGame.Team(2).Skater(*).Name',
    ];

    _log.d('Registering paths');
    _channel?.sink.add(jsonEncode({'action': 'Register', 'paths': paths}));
  }

  void _handleMessage(dynamic message) {
    _log.d('Received: $message');

    if (!_isConnected) {
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _state.setConnectionStatus(ConnectionStatus.connected, message: 'Connected');
      WakelockPlus.enable();
    }

    try {
      final decoded = jsonDecode(message as String);
      if (decoded is! Map<String, dynamic>) return;

      Map<String, dynamic>? stateMap;
      if (decoded.containsKey('state')) {
        stateMap = decoded['state'] as Map<String, dynamic>?;
      } else if (decoded.containsKey('updates')) {
        stateMap = decoded['updates'] as Map<String, dynamic>?;
      }

      if (stateMap != null) {
        _parseState(stateMap);
      }
    } catch (e) {
      _log.e('Error parsing message: $e');
    }
  }

  void _parseState(Map<String, dynamic> state) {
    bool jamWasRunning = _state.jamRunning;

    for (final entry in state.entries) {
      final key = entry.key;
      final value = entry.value;
      _parsePath(key, value);
    }

    // Trigger jam events if state changed
    final jamNowRunning = _state.jamRunning;
    if (!jamWasRunning && jamNowRunning) {
      _state.onJamStart();
    } else if (jamWasRunning && !jamNowRunning) {
      _state.onJamEnd();
    }
  }

  void _parsePath(String key, dynamic value) {
    // Jam running: ScoreBoard.CurrentGame.InJam or Clock(Jam).Running
    if (key == 'ScoreBoard.CurrentGame.InJam') {
      _state.jamRunning = value == true || value == 'true';
      return;
    }
    if (key == 'ScoreBoard.CurrentGame.Clock(Jam).Running') {
      // Only use as fallback if InJam not available
      _state.jamRunning = value == true || value == 'true';
      return;
    }
    if (key == 'ScoreBoard.CurrentGame.Clock(Jam).Number') {
      final n = _parseInt(value);
      if (n != null) _state.jamNumber = n;
      return;
    }
    if (key == 'ScoreBoard.CurrentGame.Clock(Period).Number') {
      final n = _parseInt(value);
      if (n != null) _state.periodNumber = n;
      return;
    }

    // Team names
    final teamNameMatch = RegExp(r'ScoreBoard\.CurrentGame\.Team\((\d)\)\.Name$').firstMatch(key);
    if (teamNameMatch != null) {
      final t = int.parse(teamNameMatch.group(1)!);
      _state.updateTeam(t, name: value?.toString() ?? '');
      return;
    }

    // Team colors (use operator.fg for text/accent)
    final teamColorMatch = RegExp(r'ScoreBoard\.CurrentGame\.Team\((\d)\)\.Color\(operator\.fg\)$').firstMatch(key);
    if (teamColorMatch != null) {
      final t = int.parse(teamColorMatch.group(1)!);
      final color = _parseColor(value?.toString());
      if (color != null) _state.updateTeam(t, color: color);
      return;
    }

    // Roster: ScoreBoard.CurrentGame.Team(t).Skater(uuid).Number
    final skaterMatch = RegExp(
      r'ScoreBoard\.CurrentGame\.Team\((\d)\)\.Skater\(([^)]+)\)\.Number$',
    ).firstMatch(key);
    if (skaterMatch != null) {
      final t = int.parse(skaterMatch.group(1)!);
      final skaterId = skaterMatch.group(2)!;
      final number = value?.toString() ?? '';
      if (number.isNotEmpty) _state.updateRoster(t, number, skaterId);
      return;
    }

    // Legacy roster: Game.Team(t).Skater — value is a map
    final legacySkaterMatch = RegExp(r'Game\.Team\((\d)\)\.Skater$').firstMatch(key);
    if (legacySkaterMatch != null && value is Map) {
      final t = int.parse(legacySkaterMatch.group(1)!);
      value.forEach((skaterId, skaterData) {
        if (skaterData is Map) {
          final number = skaterData['Number']?.toString() ?? '';
          if (number.isNotEmpty) _state.updateRoster(t, number, skaterId.toString());
        }
      });
      return;
    }
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  Color? _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final clean = hex.replaceFirst('#', '');
      final fullHex = clean.length == 6 ? 'FF$clean' : clean;
      return Color(int.parse(fullHex, radix: 16));
    } catch (_) {
      return null;
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeChannel();
    _disconnectCleanup();
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
      error != null ? ConnectionStatus.disconnected : ConnectionStatus.disconnected,
      message: error != null ? 'Error: $error' : 'Disconnected',
    );
    WakelockPlus.disable();
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || _lastUrl == null) return;
    if (_reconnectTimer != null || _isConnected || _isConnecting) return;

    final baseDelaySec = 1 << _reconnectAttempts;
    final cappedSec = baseDelaySec > 30 ? 30 : baseDelaySec;
    final jitterMs = _random.nextInt(500);
    final delay = Duration(seconds: cappedSec) + Duration(milliseconds: jitterMs);

    _reconnectAttempts++;
    _state.setConnectionStatus(
      ConnectionStatus.disconnected,
      message: 'Reconnecting in ${delay.inSeconds}s...',
    );

    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_manualDisconnect || _lastUrl == null) return;
      connect(_lastUrl!);
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isConnected) {
        _channel?.sink.add(jsonEncode({'action': 'Ping'}));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _localEngine.didChangeAppLifecycleState(state);
    }
  }

  @override
  Future<void> dispose() async {
    disconnect();
    await _localEngine.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void toggleJam() {
    // No manual toggle when connected — jam state driven by CRG
  }

  @override
  void reportPenalty({
    required int teamIndex,
    required String skaterNumber,
    required int periodNumber,
    required int jamNumber,
  }) {
    if (!_isConnected) return;

    final skaterId = _state.lookupSkaterId(teamIndex, skaterNumber);
    if (skaterId == null) {
      _log.w('Cannot report penalty: skater #$skaterNumber not found in roster for team $teamIndex');
      return;
    }

    final message = jsonEncode({
      'action': 'Penalty',
      'data': {
        'teamId': teamIndex.toString(),
        'skaterId': skaterId,
        'penaltyId': null,
        'fo_exp': false,
        'period': periodNumber,
        'jam': jamNumber,
        'code': '?', // Unknown code — refs track this
      },
    });

    _log.d('Reporting penalty: $message');
    _channel?.sink.add(message);
  }
}

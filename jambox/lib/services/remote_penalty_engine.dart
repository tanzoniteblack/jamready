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
import '../models/skater_seat.dart';
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
  bool _boxSeatMode = false;
  int _reconnectAttempts = 0;
  String? _lastUrl;
  final Random _random = Random();
  late final LocalPenaltyEngine _localEngine;

  // Blocker3 queue tracking for BoxSeat mode
  final Map<int, SkaterSeat?> _blocker3QueueSeat = {1: null, 2: null};

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
      // Skater role (for jammer number display in BoxSeat mode)
      'ScoreBoard.CurrentGame.Team(1).Skater(*).Role',
      'ScoreBoard.CurrentGame.Team(2).Skater(*).Role',
      // BoxSeat/BoxClock (katpet/feature-pbt — ignored silently on other versions)
      'ScoreBoard.CurrentGame.BoxClock(*).Time',
      'ScoreBoard.CurrentGame.BoxClock(*).Running',
      'ScoreBoard.CurrentGame.Team(1).BoxSeat(*).Started',
      'ScoreBoard.CurrentGame.Team(1).BoxSeat(*).BoxSkater',
      'ScoreBoard.CurrentGame.Team(2).BoxSeat(*).Started',
      'ScoreBoard.CurrentGame.Team(2).BoxSeat(*).BoxSkater',
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

    // Skater role — used in BoxSeat mode to display jammer number
    final roleMatch = RegExp(
      r'ScoreBoard\.CurrentGame\.Team\((\d)\)\.Skater\(([^)]+)\)\.Role$',
    ).firstMatch(key);
    if (roleMatch != null) {
      final t = int.parse(roleMatch.group(1)!);
      final uuid = roleMatch.group(2)!;
      _onSkaterRole(t, uuid, value?.toString() ?? '');
      return;
    }

    // BoxClock: ScoreBoard.CurrentGame.BoxClock(Team1Jammer).Time or .Running
    final boxClockMatch = RegExp(
      r'ScoreBoard\.CurrentGame\.BoxClock\(Team(\d)(Jammer|Blocker[123])\)\.(Time|Running)$',
    ).firstMatch(key);
    if (boxClockMatch != null) {
      final t = int.parse(boxClockMatch.group(1)!);
      final seatId = boxClockMatch.group(2)!;
      final prop = boxClockMatch.group(3)!;
      _onBoxClockUpdate(t, seatId, prop, value);
      return;
    }

    // BoxSeat: ScoreBoard.CurrentGame.Team(N).BoxSeat(SeatId).Started or .BoxSkater
    final boxSeatMatch = RegExp(
      r'ScoreBoard\.CurrentGame\.Team\((\d)\)\.BoxSeat\((Jammer|Blocker[123])\)\.(Started|BoxSkater)$',
    ).firstMatch(key);
    if (boxSeatMatch != null) {
      final t = int.parse(boxSeatMatch.group(1)!);
      final seatId = boxSeatMatch.group(2)!;
      final prop = boxSeatMatch.group(3)!;
      _onBoxSeatUpdate(t, seatId, prop, value);
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

  /// Send a CRG WebSocket Set command.
  void _wsSet(String key, dynamic value) {
    _channel?.sink.add(jsonEncode({'action': 'Set', 'key': key, 'value': value, 'flag': ''}));
  }

  /// Map a SkaterSeat id to (teamIndex, boxSeatId) for WS commands.
  (int?, String?) _seatToBoxSeatId(SkaterSeat seat) {
    return switch (seat.id) {
      't1j' => (1, 'Jammer'),
      't1b1' => (1, 'Blocker1'),
      't1b2' => (1, 'Blocker2'),
      't2j' => (2, 'Jammer'),
      't2b1' => (2, 'Blocker1'),
      't2b2' => (2, 'Blocker2'),
      _ => (null, null),
    };
  }

  /// Map BoxClock ID components to a SkaterSeat (null for Blocker3 → use queue).
  SkaterSeat? _boxClockToSeat(int teamIdx, String seatId) {
    return switch ('$teamIdx:$seatId') {
      '1:Jammer' => _state.team1Jammer,
      '1:Blocker1' => _state.team1Blocker1,
      '1:Blocker2' => _state.team1Blocker2,
      '2:Jammer' => _state.team2Jammer,
      '2:Blocker1' => _state.team2Blocker1,
      '2:Blocker2' => _state.team2Blocker2,
      _ => null, // Blocker3 — handled via queue
    };
  }

  /// Activate BoxSeat sync mode: pause local ticker and wire up action callbacks.
  void _enterBoxSeatMode() {
    if (_boxSeatMode) return;
    _boxSeatMode = true;
    _localEngine.pauseTicker();

    _state.onSeatStarted = (seat) {
      final (teamIdx, seatId) = _seatToBoxSeatId(seat);
      if (teamIdx != null) {
        _wsSet('ScoreBoard.CurrentGame.Team($teamIdx).BoxSeat($seatId).StartBox', true);
      }
    };
    _state.onSeatCleared = (seat) {
      final (teamIdx, seatId) = _seatToBoxSeatId(seat);
      if (teamIdx != null) {
        _wsSet('ScoreBoard.CurrentGame.Team($teamIdx).BoxSeat($seatId).ResetBox', true);
      }
    };
    _state.onSeatTimeChanged = (seat, seconds) {
      final (teamIdx, seatId) = _seatToBoxSeatId(seat);
      if (teamIdx != null) {
        _wsSet('ScoreBoard.CurrentGame.Team($teamIdx).BoxSeat($seatId).BoxTimeChange', seconds);
      }
    };
    _state.onSkaterAssigned = (seat, number) {
      final (teamIdx, seatId) = _seatToBoxSeatId(seat);
      if (teamIdx != null && seatId != 'Jammer') {
        _wsSet('ScoreBoard.CurrentGame.Team($teamIdx).BoxSeat($seatId).BoxSkater', number);
      }
    };

    _log.i('BoxSeat mode activated — local ticker paused, WS commands enabled');
  }

  void _onBoxClockUpdate(int teamIdx, String seatId, String prop, dynamic value) {
    _enterBoxSeatMode();
    final seat = _boxClockToSeat(teamIdx, seatId);
    if (seat != null) {
      if (prop == 'Time') {
        final ms = (value is num) ? value.toInt() : int.tryParse(value.toString()) ?? 0;
        seat.timeRemaining = Duration(milliseconds: ms.clamp(0, 5 * 60 * 1000));
      } else if (prop == 'Running') {
        seat.isRunning = value == true || value == 'true';
      }
    } else if (seatId == 'Blocker3' && prop == 'Time') {
      // Sync queue entry time for Blocker3
      final ms = (value is num) ? value.toInt() : int.tryParse(value.toString()) ?? 0;
      final queueSeat = _blocker3QueueSeat[teamIdx];
      if (queueSeat != null) {
        queueSeat.timeRemaining = Duration(milliseconds: ms.clamp(0, 5 * 60 * 1000));
      }
    }
    _state.notifyFromEngine();
  }

  void _onBoxSeatUpdate(int teamIdx, String seatId, String prop, dynamic value) {
    _enterBoxSeatMode();
    final seat = _boxClockToSeat(teamIdx, seatId);

    if (prop == 'Started') {
      final started = value == true || value == 'true';
      if (seatId == 'Blocker3') {
        _onBlocker3Started(teamIdx, started);
        return;
      }
      if (seat == null) return;
      if (!started) {
        seat.clear();
      } else if (seat.isEmpty) {
        seat.skaterNumber = '?'; // placeholder until BoxSkater or Role arrives
        seat.timeRemaining = const Duration(seconds: 30);
      }
    } else if (prop == 'BoxSkater') {
      final number = value?.toString() ?? '';
      if (seat == null) return;
      if (number.isEmpty) {
        if (seat.skaterNumber == '?') return; // keep placeholder
        seat.skaterNumber = '?';
      } else {
        seat.skaterNumber = number;
        _state.addKnownNumber(teamIdx, number);
      }
    }
    _state.notifyFromEngine();
  }

  void _onBlocker3Started(int teamIdx, bool started) {
    if (started) {
      if (_blocker3QueueSeat[teamIdx] == null) {
        final q = _state.addToQueue(
          teamIdx: teamIdx,
          number: '?',
          position: SkaterPosition.blocker,
        );
        _blocker3QueueSeat[teamIdx] = q;
      }
    } else {
      final q = _blocker3QueueSeat[teamIdx];
      if (q != null) {
        _state.removeFromQueue(q);
        _blocker3QueueSeat[teamIdx] = null;
      }
    }
  }

  void _onSkaterRole(int teamIdx, String uuid, String role) {
    if (role != 'Jammer') return;
    final number = _state.skaterNumberByUuid(teamIdx, uuid);
    if (number == null || number.isEmpty) return;
    final seat = _state.jammerSeat(teamIdx);
    if (seat.skaterNumber != number) {
      seat.skaterNumber = number;
      _state.notifyFromEngine();
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
    _state.clearBoxSeatCallbacks();
    await _localEngine.dispose();
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void toggleJam() {
    // No manual toggle when connected — jam state driven by CRG
  }

  @override
  Future<void> reconnect() async {
    if (_lastUrl == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _closeChannel();
    _disconnectCleanup();
    // Reset BoxSeat mode so it's re-detected on fresh connection
    _boxSeatMode = false;
    _blocker3QueueSeat[1] = null;
    _blocker3QueueSeat[2] = null;
    _state.clearBoxSeatCallbacks();
    _localEngine.resumeTicker();
    await connect(_lastUrl!);
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

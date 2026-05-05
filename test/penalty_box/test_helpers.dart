import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:jam_ready/models/penalty_box_state.dart';
import 'package:jam_ready/models/skater_seat.dart';

// ---------------------------------------------------------------------------
// Fake WebSocket infrastructure
// ---------------------------------------------------------------------------

class FakeWebSocketSink implements WebSocketSink {
  final List<Map<String, dynamic>> sent = [];

  @override
  void add(dynamic data) =>
      sent.add(jsonDecode(data as String) as Map<String, dynamic>);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  Future<void> get done => Completer<void>().future;

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}
}

class FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _controller = StreamController<dynamic>();

  @override
  final FakeWebSocketSink sink = FakeWebSocketSink();

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  Future<void> get ready => Future.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  /// Push a CRG-style state update: `{"state": stateMap}`.
  void send(Map<String, dynamic> stateMap) =>
      _controller.add(jsonEncode({'state': stateMap}));

  /// All WS commands sent by the engine (decoded JSON).
  List<Map<String, dynamic>> get sent => sink.sent;

  /// Commands matching a given action string (e.g. 'Set', 'Penalty').
  List<Map<String, dynamic>> sentWithAction(String action) =>
      sent.where((m) => m['action'] == action).toList();

  /// Set commands whose key contains [keyFragment].
  List<Map<String, dynamic>> sentSets(String keyFragment) => sent
      .where(
        (m) =>
            m['action'] == 'Set' && (m['key'] as String).contains(keyFragment),
      )
      .toList();

  void dispose() => _controller.close();
}

// ---------------------------------------------------------------------------
// State builders
// ---------------------------------------------------------------------------

PenaltyBoxState makeState({AppRole role = AppRole.pbm, int? teamIndex}) =>
    PenaltyBoxState(role: role, teamIndex: teamIndex);

/// Seats a jammer for [team] with [number]. If [penalties] > 1 the extra
/// penalties are included at seating time so the sync sees the full count.
/// Returns the seat.
SkaterSeat seatJammer(
  PenaltyBoxState state,
  int team,
  String number, {
  int penalties = 1,
}) {
  final seat = state.jammerSeat(team);
  state.seatSkater(
    seat: seat,
    number: number,
    position: SkaterPosition.jammer,
    penaltyCount: penalties,
  );
  return seat;
}

/// Seats a blocker in the first available blocker seat for [team].
SkaterSeat seatBlocker(
  PenaltyBoxState state,
  int team,
  String number, {
  int seatIndex = 0,
}) {
  final seat = state.blockerSeats(team)[seatIndex];
  state.seatSkater(
    seat: seat,
    number: number,
    position: SkaterPosition.blocker,
  );
  return seat;
}

// ---------------------------------------------------------------------------
// Custom matchers / assertion helpers
// ---------------------------------------------------------------------------

void expectSeatEmpty(SkaterSeat seat) {
  expect(seat.isEmpty, isTrue, reason: 'Expected seat ${seat.id} to be empty');
}

void expectSeatOccupied(SkaterSeat seat, String number) {
  expect(
    seat.skaterNumber,
    number,
    reason: 'Expected seat ${seat.id} to have skater $number',
  );
}

void expectSeatState(SkaterSeat seat, SeatState expected) {
  expect(
    seat.state,
    expected,
    reason: 'Expected seat ${seat.id} state to be $expected',
  );
}

void expectTimeRemaining(SkaterSeat seat, Duration expected) {
  expect(
    seat.timeRemaining,
    expected,
    reason: 'Expected seat ${seat.id} timeRemaining to be $expected',
  );
}

void expectJammerTimes(
  PenaltyBoxState state, {
  required Duration team1,
  required Duration team2,
}) {
  expect(
    state.team1Jammer.timeRemaining,
    team1,
    reason: 'T1 jammer time mismatch',
  );
  expect(
    state.team2Jammer.timeRemaining,
    team2,
    reason: 'T2 jammer time mismatch',
  );
}

void expectNoCommandSent(FakeWebSocketChannel channel) {
  expect(channel.sent, isEmpty, reason: 'Expected no WS commands to be sent');
}

void expectCommandSent(FakeWebSocketChannel channel, String keyFragment) {
  final matches = channel.sentSets(keyFragment);
  expect(
    matches,
    isNotEmpty,
    reason: 'Expected a Set command containing "$keyFragment"',
  );
}

void expectCommandNotSent(FakeWebSocketChannel channel, String keyFragment) {
  final matches = channel.sentSets(keyFragment);
  expect(
    matches,
    isEmpty,
    reason: 'Expected no Set command containing "$keyFragment"',
  );
}

import 'package:flutter/material.dart';
import 'skater_seat.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class TeamInfo {
  final int index;
  String name;
  Color color;

  TeamInfo({required this.index, this.name = '', Color? color})
    : color = color ?? (index == 1 ? Colors.blue.shade400 : Colors.red.shade400);
}

class PenaltyBoxState extends ChangeNotifier {
  AppRole role;
  int? teamIndex; // for boxTimer role

  ConnectionStatus connectionStatus = ConnectionStatus.disconnected;
  String connectionMessage = 'Disconnected';

  bool jamRunning = false;
  int periodNumber = 1;
  int jamNumber = 0;

  // Team info loaded from CRG
  final TeamInfo team1 = TeamInfo(index: 1, name: 'Team 1');
  final TeamInfo team2 = TeamInfo(index: 2, name: 'Team 2');

  // Roster from CRG: skaterNumber -> skaterId (uuid)
  final Map<String, String> _rosterTeam1 = {};
  final Map<String, String> _rosterTeam2 = {};

  // Active seats: indexed by seat id
  // Seat layout: team1Jammer, team1Blocker1, team1Blocker2, team2Jammer, team2Blocker1, team2Blocker2
  final List<SkaterSeat> seats = [
    SkaterSeat(id: 't1j', teamIndex: 1, position: SkaterPosition.jammer),
    SkaterSeat(id: 't1b1', teamIndex: 1, position: SkaterPosition.blocker),
    SkaterSeat(id: 't1b2', teamIndex: 1, position: SkaterPosition.blocker),
    SkaterSeat(id: 't2j', teamIndex: 2, position: SkaterPosition.jammer),
    SkaterSeat(id: 't2b1', teamIndex: 2, position: SkaterPosition.blocker),
    SkaterSeat(id: 't2b2', teamIndex: 2, position: SkaterPosition.blocker),
  ];

  // Queue: skaters waiting for a seat to open (3rd+ blocker)
  final List<SkaterSeat> queue = [];
  int _queueIdCounter = 0;

  PenaltyBoxState({this.role = AppRole.pbm, this.teamIndex});

  TeamInfo teamInfo(int idx) => idx == 1 ? team1 : team2;

  SkaterSeat get team1Jammer => seats[0];
  SkaterSeat get team1Blocker1 => seats[1];
  SkaterSeat get team1Blocker2 => seats[2];
  SkaterSeat get team2Jammer => seats[3];
  SkaterSeat get team2Blocker1 => seats[4];
  SkaterSeat get team2Blocker2 => seats[5];

  SkaterSeat jammerSeat(int teamIdx) => teamIdx == 1 ? team1Jammer : team2Jammer;

  List<SkaterSeat> blockerSeats(int teamIdx) =>
      teamIdx == 1 ? [team1Blocker1, team1Blocker2] : [team2Blocker1, team2Blocker2];

  List<SkaterSeat> queueForTeam(int teamIdx) =>
      queue.where((s) => s.teamIndex == teamIdx).toList();

  void setConnectionStatus(ConnectionStatus status, {String? message}) {
    connectionStatus = status;
    connectionMessage = message ?? status.name;
    notifyListeners();
  }

  void updateTeam(int teamIdx, {String? name, Color? color}) {
    final t = teamInfo(teamIdx);
    if (name != null) t.name = name.isNotEmpty ? name : 'Team $teamIdx';
    if (color != null) t.color = color;
    notifyListeners();
  }

  void updateRoster(int teamIdx, String skaterNumber, String skaterId) {
    if (teamIdx == 1) {
      _rosterTeam1[skaterNumber] = skaterId;
    } else {
      _rosterTeam2[skaterNumber] = skaterId;
    }
    // no listener notification needed — roster changes don't affect UI directly
  }

  String? lookupSkaterId(int teamIdx, String skaterNumber) {
    return teamIdx == 1 ? _rosterTeam1[skaterNumber] : _rosterTeam2[skaterNumber];
  }

  void onJamStart() {
    jamRunning = true;

    // Jammer sync: if a jammer arrived between jams, they start their timer now
    for (final seat in [team1Jammer, team2Jammer]) {
      if (seat.isOccupied && seat.arrivedBetweenJams) {
        seat.isRunning = true;
        seat.arrivedBetweenJams = false;
      }
    }

    // Release jammers that were marked for release at jam start
    _applyJammerSync();

    // Start all occupied blocker timers
    for (final seat in seats) {
      if (seat.isOccupied && !seat.isRunning && seat.position != SkaterPosition.jammer) {
        seat.isRunning = true;
      }
    }

    notifyListeners();
  }

  void onJamEnd() {
    jamRunning = false;
    // Pause all running timers
    for (final seat in seats) {
      seat.isRunning = false;
    }
    notifyListeners();
  }

  void _applyJammerSync() {
    // WFTDA 4.4: when both jammers were seated between jams, both release at jam start
    // (i.e. their time was already at 0 or they are done — handled by done state)
    // If one jammer was sitting between jams while the other was not,
    // the between-jams jammer releases at next jam start.
    // This is handled by: if arrivedBetweenJams AND time <= 0 → clear seat
    for (final seat in [team1Jammer, team2Jammer]) {
      if (seat.isOccupied && seat.timeRemaining <= Duration.zero) {
        seat.clear();
      }
    }
  }

  void setJamInfo(int period, int jam) {
    periodNumber = period;
    jamNumber = jam;
    notifyListeners();
  }

  /// Called each timer tick (typically every 100ms) to decrement running seats.
  void tick(Duration elapsed) {
    bool changed = false;
    for (final seat in seats) {
      if (seat.isRunning && seat.timeRemaining > Duration.zero) {
        seat.timeRemaining -= elapsed;
        if (seat.timeRemaining < Duration.zero) {
          seat.timeRemaining = Duration.zero;
        }
        if (seat.timeRemaining <= Duration.zero) {
          seat.isRunning = false;
        }
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // --- Seat management actions ---

  void seatSkater({
    required SkaterSeat seat,
    required String number,
    required SkaterPosition position,
    bool fouledOut = false,
  }) {
    seat.setSkater(
      number: number,
      pos: position,
      fouledOut: fouledOut,
      arrivedBetween: !jamRunning,
    );
    if (jamRunning && position != SkaterPosition.jammer) {
      seat.isRunning = true;
    }
    notifyListeners();
  }

  void addPenaltyToSeat(SkaterSeat seat) {
    seat.addPenalty();
    if (jamRunning && !seat.isRunning) {
      seat.isRunning = true;
    }
    notifyListeners();
  }

  void clearSeat(SkaterSeat seat) {
    // Check if there's someone in queue to fill this seat
    final teamQueue = queueForTeam(seat.teamIndex);
    if (teamQueue.isNotEmpty && seat.position != SkaterPosition.jammer) {
      final next = teamQueue.first;
      queue.remove(next);
      seat.setSkater(
        number: next.skaterNumber,
        pos: next.position,
        fouledOut: next.isFouledOut,
        arrivedBetween: !jamRunning,
      );
      if (jamRunning) seat.isRunning = true;
    } else {
      seat.clear();
    }
    notifyListeners();
  }

  /// Adds a blocker to the queue (3rd blocker from same team).
  SkaterSeat addToQueue({
    required int teamIdx,
    required String number,
    required SkaterPosition position,
  }) {
    final queued = SkaterSeat(
      id: 'q${_queueIdCounter++}',
      teamIndex: teamIdx,
      position: position,
    );
    queued.skaterNumber = number;
    queue.add(queued);
    notifyListeners();
    return queued;
  }

  void removeFromQueue(SkaterSeat seat) {
    queue.remove(seat);
    notifyListeners();
  }

  void startJammerTimer(int teamIdx) {
    final seat = jammerSeat(teamIdx);
    if (seat.isOccupied && jamRunning) {
      seat.isRunning = true;
      notifyListeners();
    }
  }
}

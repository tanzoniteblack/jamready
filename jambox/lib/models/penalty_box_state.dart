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

  // Known skater numbers (from roster + local history)
  final Set<String> _knownNumbersTeam1 = {};
  final Set<String> _knownNumbersTeam2 = {};

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

  void setTeamColor(int teamIdx, Color color) => updateTeam(teamIdx, color: color);

  void updateRoster(int teamIdx, String skaterNumber, String skaterId) {
    if (teamIdx == 1) {
      _rosterTeam1[skaterNumber] = skaterId;
    } else {
      _rosterTeam2[skaterNumber] = skaterId;
    }
    addKnownNumber(teamIdx, skaterNumber);
    // no listener notification needed — roster changes don't affect UI directly
  }

  String? lookupSkaterId(int teamIdx, String skaterNumber) {
    return teamIdx == 1 ? _rosterTeam1[skaterNumber] : _rosterTeam2[skaterNumber];
  }

  List<String> knownNumbers(int teamIdx) {
    final s = teamIdx == 1 ? _knownNumbersTeam1 : _knownNumbersTeam2;
    return s.toList()..sort();
  }

  void addKnownNumber(int teamIdx, String number) {
    if (number.isEmpty || number == '?') return;
    (teamIdx == 1 ? _knownNumbersTeam1 : _knownNumbersTeam2).add(number);
  }

  void onJamStart() {
    jamRunning = true;

    // Start all occupied seat timers (jammers included — they auto-start on jam start)
    for (final seat in seats) {
      if (seat.isOccupied && !seat.isRunning) {
        seat.isRunning = true;
      }
      seat.arrivedBetweenJams = false;
    }

    // Release jammers at 0:00 that have served their time between jams
    _applyJammerSync();

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
    // WFTDA 4.4: jammers who are done (0:00) at jam start are released
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
  }) {
    seat.setSkater(
      number: number,
      pos: position,
      arrivedBetween: !jamRunning,
    );
    if (jamRunning) {
      seat.isRunning = true;
    }
    notifyListeners();
  }

  /// Starts a seat immediately with placeholder number '?' — timer runs if jam is running
  /// and position is not jammer (jammers require manual start).
  void startSeatAnonymously(SkaterSeat seat) {
    seat.skaterNumber = '?';
    seat.timeRemaining = const Duration(seconds: 30);
    seat.arrivedBetweenJams = !jamRunning;
    seat.isRunning = jamRunning;
    notifyListeners();
  }

  /// Updates the skater number (and optionally position) on an already-running seat.
  void setSkaterNumber(SkaterSeat seat, String number, {SkaterPosition? position}) {
    seat.skaterNumber = number;
    if (position != null) seat.position = position;
    addKnownNumber(seat.teamIndex, number);
    notifyListeners();
  }

  void addPenaltyToSeat(SkaterSeat seat) {
    seat.addPenalty();
    if (jamRunning && !seat.isRunning) {
      seat.isRunning = true;
    }
    notifyListeners();
  }

  void adjustTime(SkaterSeat seat, Duration delta) {
    final newTime = seat.timeRemaining + delta;
    seat.timeRemaining = newTime.isNegative ? Duration.zero : newTime > const Duration(minutes: 5) ? const Duration(minutes: 5) : newTime;
    if (seat.timeRemaining > Duration.zero && !seat.isRunning && jamRunning) seat.isRunning = true;
    if (seat.timeRemaining <= Duration.zero) seat.isRunning = false;
    notifyListeners();
  }

  void removePenaltyFromSeat(SkaterSeat seat) {
    seat.timeRemaining -= const Duration(seconds: 30);
    if (seat.timeRemaining <= Duration.zero) {
      seat.timeRemaining = Duration.zero;
      seat.isRunning = false;
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

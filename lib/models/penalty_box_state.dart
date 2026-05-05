import 'package:flutter/material.dart';
import 'skater_seat.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class TeamInfo {
  final int index;
  String name;

  Color? _operatorFg;
  Color? _operatorBg;
  Color? _operatorGlow;
  Color? _penaltyFg;
  Color? _penaltyBg;
  Color? _penaltyGlow;
  Color? _localColor;
  Color? _localFg;
  Color? _localBg;
  Color? _localGlow;

  TeamInfo({required this.index, this.name = '', Color? color})
    : _localColor = color;

  Color get _default => index == 1 ? Colors.white : Colors.black;

  /// Foreground color: penalty > operator > local/default.
  Color get fgColor =>
      _penaltyFg ?? _operatorFg ?? _localFg ?? _localColor ?? _default;

  /// Background color: penalty > operator > local/default.
  Color get bgColor =>
      _penaltyBg ?? _operatorBg ?? _localBg ?? _localColor ?? _default;

  /// Glow/accent color: penalty > operator > local/default.
  Color get glowColor =>
      _penaltyGlow ??
      _operatorGlow ??
      _localGlow ??
      _localFg ??
      _localColor ??
      _default;

  /// Primary team color (fg). Kept for backward compat with UI.
  Color get color => fgColor;
  set color(Color c) {
    _localColor = c;
    _localFg = c;
    _localBg = c;
    _localGlow = c;
  }

  void setLocalColors({Color? fg, Color? bg, Color? glow}) {
    if (fg != null) _localFg = fg;
    if (bg != null) _localBg = bg;
    if (glow != null) _localGlow = glow;
  }

  void setRemoteColor(String source, String channel, Color color) {
    switch ((source, channel)) {
      case ('operator', 'fg'):
        _operatorFg = color;
      case ('operator', 'bg'):
        _operatorBg = color;
      case ('operator', 'glow'):
        _operatorGlow = color;
      case ('penalty', 'fg'):
        _penaltyFg = color;
      case ('penalty', 'bg'):
        _penaltyBg = color;
      case ('penalty', 'glow'):
        _penaltyGlow = color;
    }
  }
}

class PenaltyBoxState extends ChangeNotifier {
  AppRole role;
  int? teamIndex; // for boxTimer role

  ConnectionStatus connectionStatus = ConnectionStatus.disconnected;
  String connectionMessage = 'Disconnected';

  bool jamRunning = false;
  int periodNumber = 1;
  int jamNumber = 0;

  // Set to true when CRG sends team names; used to detect remote name updates.
  bool teamNamesFromRemote = false;

  // Team info loaded from CRG (defaults to Salt/Pepper for local/offline use)
  final TeamInfo team1 = TeamInfo(index: 1, name: 'Salt', color: Colors.white);
  final TeamInfo team2 = TeamInfo(
    index: 2,
    name: 'Pepper',
    color: Colors.black,
  );

  // Roster from CRG: skaterNumber -> skaterId (uuid)
  final Map<String, String> _rosterTeam1 = {};
  final Map<String, String> _rosterTeam2 = {};

  // Known skater numbers (from roster + local history)
  final Set<String> _knownNumbersTeam1 = {};
  final Set<String> _knownNumbersTeam2 = {};

  // Active seats: indexed by seat id
  // Seat layout (4 per team): jammer, blocker1–3
  // Team-1: idx 0–3; Team-2: idx 4–7
  final List<SkaterSeat> seats = [
    SkaterSeat(id: 't1j', teamIndex: 1, position: SkaterPosition.jammer),
    SkaterSeat(id: 't1b1', teamIndex: 1, position: SkaterPosition.blocker),
    SkaterSeat(id: 't1b2', teamIndex: 1, position: SkaterPosition.blocker),
    SkaterSeat(id: 't1b3', teamIndex: 1, position: SkaterPosition.blocker),
    SkaterSeat(id: 't2j', teamIndex: 2, position: SkaterPosition.jammer),
    SkaterSeat(id: 't2b1', teamIndex: 2, position: SkaterPosition.blocker),
    SkaterSeat(id: 't2b2', teamIndex: 2, position: SkaterPosition.blocker),
    SkaterSeat(id: 't2b3', teamIndex: 2, position: SkaterPosition.blocker),
  ];

  // Queue: skaters waiting for a seat to open (3rd+ blocker)
  final List<SkaterSeat> queue = [];
  int _queueIdCounter = 0;

  PenaltyBoxState({this.role = AppRole.pbm, this.teamIndex});

  TeamInfo teamInfo(int idx) => idx == 1 ? team1 : team2;

  int? get teamIndexFromRole => switch (role) {
    AppRole.team1BlockersOnly || AppRole.team1Full => 1,
    AppRole.team2Full || AppRole.team2BlockersOnly => 2,
    _ => null,
  };

  SkaterSeat get team1Jammer => seats[0];
  SkaterSeat get team1Blocker1 => seats[1];
  SkaterSeat get team1Blocker2 => seats[2];
  SkaterSeat get team1Blocker3 => seats[3];
  SkaterSeat get team2Jammer => seats[4];
  SkaterSeat get team2Blocker1 => seats[5];
  SkaterSeat get team2Blocker2 => seats[6];
  SkaterSeat get team2Blocker3 => seats[7];

  SkaterSeat jammerSeat(int teamIdx) =>
      teamIdx == 1 ? team1Jammer : team2Jammer;

  List<SkaterSeat> blockerSeats(int teamIdx) => teamIdx == 1
      ? [team1Blocker1, team1Blocker2, team1Blocker3]
      : [team2Blocker1, team2Blocker2, team2Blocker3];

  List<SkaterSeat> queueForTeam(int teamIdx) =>
      queue.where((s) => s.teamIndex == teamIdx).toList();

  void setConnectionStatus(ConnectionStatus status, {String? message}) {
    connectionStatus = status;
    connectionMessage = message ?? status.name;
    notifyListeners();
  }

  void updateTeam(
    int teamIdx, {
    String? name,
    Color? color,
    Color? fgColor,
    Color? bgColor,
  }) {
    final t = teamInfo(teamIdx);
    if (name != null) {
      t.name = name.isNotEmpty ? name : (teamIdx == 1 ? 'Salt' : 'Pepper');
      teamNamesFromRemote = true;
    }
    if (color != null) t.color = color;
    if (fgColor != null || bgColor != null) {
      t.setLocalColors(fg: fgColor, bg: bgColor, glow: fgColor ?? bgColor);
    }
    notifyListeners();
  }

  void setTeamColor(int teamIdx, Color color) =>
      updateTeam(teamIdx, color: color);

  void updateTeamColor(
    int teamIdx,
    String source,
    String channel,
    Color color,
  ) {
    teamInfo(teamIdx).setRemoteColor(source, channel, color);
    notifyListeners();
  }

  void updateRoster(int teamIdx, String skaterNumber, String skaterId) {
    if (teamIdx == 1) {
      _rosterTeam1[skaterNumber] = skaterId;
    } else {
      _rosterTeam2[skaterNumber] = skaterId;
    }
    recordSkaterUuid(teamIdx, skaterId, skaterNumber);
    addKnownNumber(teamIdx, skaterNumber);
    // no listener notification needed — roster changes don't affect UI directly
  }

  String? lookupSkaterId(int teamIdx, String skaterNumber) {
    return teamIdx == 1
        ? _rosterTeam1[skaterNumber]
        : _rosterTeam2[skaterNumber];
  }

  // Reverse UUID→number lookup (used by engine for Role=Jammer mapping)
  final Map<String, String> _uuidToNumber1 = {};
  final Map<String, String> _uuidToNumber2 = {};

  void recordSkaterUuid(int teamIdx, String uuid, String number) {
    (teamIdx == 1 ? _uuidToNumber1 : _uuidToNumber2)[uuid] = number;
  }

  String? skaterNumberByUuid(int teamIdx, String uuid) =>
      (teamIdx == 1 ? _uuidToNumber1 : _uuidToNumber2)[uuid];

  VoidCallback? _onKnownNumbersChanged;

  void setKnownNumbersSaveCallback(VoidCallback? cb) =>
      _onKnownNumbersChanged = cb;

  // BoxSeat action callbacks — set by RemotePenaltyEngine when in BoxSeat sync mode.
  // null = local mode (no WS commands sent).
  void Function(SkaterSeat)? onSeatStarted;
  void Function(SkaterSeat)? onSeatCleared;
  void Function(SkaterSeat, int seconds)? onSeatTimeChanged;
  void Function(SkaterSeat, String number)? onSkaterAssigned;
  void Function(SkaterSeat, bool running)? onSeatRunningChanged;

  /// Called by the remote engine to push UI updates when seat state is mutated directly.
  void notifyFromEngine() => notifyListeners();

  void clearBoxSeatCallbacks() {
    onSeatStarted = null;
    onSeatCleared = null;
    onSeatTimeChanged = null;
    onSkaterAssigned = null;
    onSeatRunningChanged = null;
  }

  List<String> knownNumbers(int teamIdx) {
    final s = teamIdx == 1 ? _knownNumbersTeam1 : _knownNumbersTeam2;
    return s.toList()..sort();
  }

  void addKnownNumber(int teamIdx, String number) {
    if (number.isEmpty || number == '?') return;
    final set = teamIdx == 1 ? _knownNumbersTeam1 : _knownNumbersTeam2;
    if (set.add(number)) _onKnownNumbersChanged?.call();
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

  /// WFTDA §4.4 — jammer arrival sync.
  /// Called when a jammer is seated while a jam is running and the other
  /// jammer is already serving time. Synchronizes both clocks per the rules.
  ///
  /// Uses [unmatchedPenalties] instead of [penaltyCount] so penalties that
  /// were already paired in a prior swap are never re-matched.
  void _applyJammerArrivalSync(SkaterSeat arriving) {
    const pd = Duration(seconds: 30);
    final sitting = jammerSeat(arriving.teamIndex == 1 ? 2 : 1);
    if (!sitting.isOccupied || !sitting.isRunning) return;
    // All of sitting's penalties already matched — arriving serves full time
    if (sitting.unmatchedPenalties == 0) return;

    var sittingMax = pd * sitting.unmatchedPenalties;
    var arrivingMax = pd * arriving.penaltyCount;
    // Clamp sitting's eligible time to the unmatched portion
    var sittingTime = sitting.timeRemaining < sittingMax
        ? sitting.timeRemaining
        : sittingMax;
    var arrivingTime = arrivingMax;

    // Cancel penalty pairs one-for-one (§4.4.2)
    while (sittingTime >= pd && arrivingTime >= pd) {
      sittingTime -= pd;
      arrivingTime -= pd;
      sittingMax -= pd;
      arrivingMax -= pd;
    }

    if (sittingMax == Duration.zero || arrivingMax == Duration.zero) {
      // One side fully cancelled — values already correct after loop
      sitting.unmatchedPenalties = sittingMax.inSeconds ~/ 30;
      arriving.unmatchedPenalties = arrivingMax.inSeconds ~/ 30;
    } else if (sittingMax <= arrivingMax) {
      // §4.4.1 (extended): sitting released; arriving serves elapsed + any
      // extra unmatched penalties beyond what sitting had
      final elapsed = sittingMax - sittingTime;
      arrivingTime = elapsed + (arrivingMax - sittingMax);
      sittingTime = Duration.zero;
      sitting.unmatchedPenalties = 0;
      arriving.unmatchedPenalties = (arrivingMax - sittingMax).inSeconds ~/ 30;
    } else {
      // §4.4.3 nightmare: sitting has more unmatched — keep existing times
      arrivingTime = arrivingMax;
      sittingTime = sitting.timeRemaining;
      // unmatchedPenalties unchanged for both
    }

    arriving.timeRemaining = arrivingTime;
    if (sittingTime < sitting.timeRemaining) {
      sitting.timeRemaining = sittingTime;
    }
    if (sitting.timeRemaining <= Duration.zero) sitting.isRunning = false;
    if (arrivingTime <= Duration.zero) arriving.isRunning = false;
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
    int penaltyCount = 1,
  }) {
    seat.setSkater(number: number, pos: position, arrivedBetween: !jamRunning);
    // Add extra penalties before sync so the sync sees the full count
    for (var i = 1; i < penaltyCount; i++) {
      seat.addPenalty();
    }
    if (jamRunning) {
      seat.isRunning = true;
      if (position == SkaterPosition.jammer) _applyJammerArrivalSync(seat);
    }
    onSeatStarted?.call(seat);
    onSkaterAssigned?.call(seat, number);
    notifyListeners();
  }

  /// Starts a seat immediately with placeholder number '?' — timer runs if jam is running.
  void startSeatAnonymously(SkaterSeat seat) {
    seat.skaterNumber = '?';
    seat.timeRemaining = const Duration(seconds: 30);
    seat.penaltyCount = 1;
    seat.unmatchedPenalties = 1;
    seat.arrivedBetweenJams = !jamRunning;
    seat.isRunning = jamRunning;
    if (jamRunning && seat.position == SkaterPosition.jammer) {
      _applyJammerArrivalSync(seat);
    }
    onSeatStarted?.call(seat);
    notifyListeners();
  }

  /// Updates the skater number (and optionally position) on an already-running seat.
  void setSkaterNumber(
    SkaterSeat seat,
    String number, {
    SkaterPosition? position,
  }) {
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
    onSeatTimeChanged?.call(seat, 30);
    notifyListeners();
  }

  void adjustTime(SkaterSeat seat, Duration delta) {
    final newTime = seat.timeRemaining + delta;
    seat.timeRemaining = newTime.isNegative
        ? Duration.zero
        : newTime > const Duration(minutes: 5)
        ? const Duration(minutes: 5)
        : newTime;
    if (seat.timeRemaining > Duration.zero && !seat.isRunning && jamRunning) {
      seat.isRunning = true;
    }
    if (seat.timeRemaining <= Duration.zero) seat.isRunning = false;
    onSeatTimeChanged?.call(seat, delta.inSeconds);
    notifyListeners();
  }

  void removePenaltyFromSeat(SkaterSeat seat) {
    seat.removePenalty();
    seat.timeRemaining -= const Duration(seconds: 30);
    if (seat.timeRemaining <= Duration.zero) {
      seat.timeRemaining = Duration.zero;
      seat.isRunning = false;
    }
    onSeatTimeChanged?.call(seat, -30);
    notifyListeners();
  }

  void clearSeat(SkaterSeat seat) {
    // In BoxSeat mode, always clear locally and let server confirm.
    // In local mode, promote from queue if available.
    final teamQueue = queueForTeam(seat.teamIndex);
    if (onSeatCleared == null &&
        teamQueue.isNotEmpty &&
        seat.position != SkaterPosition.jammer) {
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
    onSeatCleared?.call(seat);
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

  void toggleSeatTimer(SkaterSeat seat) {
    if (!seat.isOccupied || seat.timeRemaining <= Duration.zero) return;
    seat.isRunning = !seat.isRunning;
    onSeatRunningChanged?.call(seat, seat.isRunning);
    notifyListeners();
  }

  void startJammerTimer(int teamIdx) {
    final seat = jammerSeat(teamIdx);
    if (seat.isOccupied && jamRunning) {
      seat.isRunning = true;
      onSeatStarted?.call(seat);
      notifyListeners();
    }
  }
}

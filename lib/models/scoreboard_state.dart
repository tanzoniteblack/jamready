import 'package:flutter/foundation.dart';

class ScoreboardState extends ChangeNotifier {
  // Connection Status
  String _connectionStatus = "Disconnected";
  String get connectionStatus => _connectionStatus;

  void setConnectionStatus(String status) {
    _connectionStatus = status;
    notifyListeners();
  }

  /// `true` when connected to a CRG server.
  bool get isConnected => _connectionStatus == "Connected";

  /// `true` while the connection is being established or re-established.
  bool get isConnecting =>
      _connectionStatus.startsWith("Connecting") ||
      _connectionStatus.startsWith("Reconnecting");

  /// `true` when a timeout or official review is in progress.
  /// Primary signal is the timeout clock running; label/owner are fallbacks
  /// for transient update ordering differences from remote servers.
  bool get inTimeout =>
      (clocks['Timeout']?.running ?? false) ||
      timeoutOwner.isNotEmpty ||
      labelStop == "End Timeout";

  /// `true` when an official review (rather than a regular timeout) is active.
  bool get isOfficialReview =>
      officialReview == "true" || officialReview == "True";

  /// `true` when there is a real undo action available.
  /// Handles both the local engine sentinel ("No Action") and the CRG
  /// server sentinel ("---").
  bool get hasUndoAction => labelUndo != "No Action" && labelUndo != "---";

  // Clocks
  Map<String, Clock> clocks = {
    'Period': Clock(name: 'Period'),
    'Jam': Clock(name: 'Jam'),
    'Lineup': Clock(name: 'Lineup'),
    'Timeout': Clock(name: 'Timeout'),
    'Intermission': Clock(name: 'Intermission'),
  };

  // Game State Flags
  String gameId = "";
  bool inJam = false;
  bool noMoreJam = false;
  bool inOvertime = false;
  bool injuryContinuationUpcoming = false;
  String timeoutOwner = "";
  String officialReview = "";

  // Teams
  Team team1 = Team(id: '1');
  Team team2 = Team(id: '2');

  // Labels
  String labelStart = "Start";
  String labelStop = "Stop";
  String labelTimeout = "Timeout";
  String labelUndo = "Undo";
  String labelReplaced = "Replaced";

  // Rules
  int lineupDuration = 30000;
  int lineupOvertimeDuration = 30000;
  bool injuryContinuationRule = false;

  void updateFromMap(Map<String, dynamic> data) {
    data.forEach((key, value) {
      _updateSinglePath(key, value);
    });
    notifyListeners();
  }

  /// Notify listeners of state changes.
  /// Used by game engines to trigger UI updates.
  void notify() {
    notifyListeners();
  }

  void _updateSinglePath(String path, dynamic value) {
    if (path.startsWith('ScoreBoard.CurrentGame.Clock(')) {
      _updateClock(path, value);
    } else if (path.startsWith('ScoreBoard.CurrentGame.Team(')) {
      _updateTeam(path, value);
    } else if (path.startsWith('ScoreBoard.CurrentGame.Label(')) {
      _updateLabel(path, value);
    } else {
      switch (path) {
        case 'ScoreBoard.CurrentGame.Game':
          gameId = value.toString();
          break;
        case 'ScoreBoard.CurrentGame.InJam':
          inJam = value == true;
          break;
        case 'ScoreBoard.CurrentGame.NoMoreJam':
          noMoreJam = value == true;
          break;
        case 'ScoreBoard.CurrentGame.InOvertime':
          inOvertime = value == true;
          break;
        case 'ScoreBoard.CurrentGame.TimeoutOwner':
          timeoutOwner = value.toString();
          break;
        case 'ScoreBoard.CurrentGame.OfficialReview':
          officialReview = value.toString();
          break;
        case 'ScoreBoard.CurrentGame.InjuryContinuationUpcoming':
          injuryContinuationUpcoming = value == true;
          break;
        case 'ScoreBoard.CurrentGame.Rule(Jam.InjuryContinuation)':
          injuryContinuationRule = value == true;
          break;
        case 'ScoreBoard.CurrentGame.Rule(Lineup.Duration)':
          if (value is int) lineupDuration = value;
          break;
        case 'ScoreBoard.CurrentGame.Rule(Lineup.OvertimeDuration)':
          if (value is int) lineupOvertimeDuration = value;
          break;
      }
    }
  }

  void _updateClock(String path, dynamic value) {
    final regex = RegExp(r'ScoreBoard\.CurrentGame\.Clock\((.+?)\)\.(.+)');
    final match = regex.firstMatch(path);
    if (match != null) {
      final clockName = match.group(1)!;
      final property = match.group(2)!;

      if (clocks.containsKey(clockName)) {
        final clock = clocks[clockName]!;
        switch (property) {
          case 'Time':
            clock.time = value as int;
            break;
          case 'Running':
            clock.running = value == true;
            break;
          case 'Name':
            clock.displayName = value.toString();
            break;
          case 'Number':
            clock.number = value is int
                ? value
                : int.tryParse(value.toString()) ?? 0;
            break;
        }
      }
    }
  }

  void _updateTeam(String path, dynamic value) {
    final regex = RegExp(r'ScoreBoard\.CurrentGame\.Team\(([12])\)\.(.+)');
    final match = regex.firstMatch(path);
    if (match != null) {
      final teamId = match.group(1)!;
      final property = match.group(2)!;
      final team = teamId == '1' ? team1 : team2;

      switch (property) {
        case 'Name':
          team.name = value.toString();
          break;
        case 'AlternateName(Operator)':
          team.alternateName = value.toString();
          break;
        case 'Score':
          team.score = value as int;
          break;
        case 'Timeouts':
          team.timeouts = value as int;
          break;
        case 'OfficialReviews':
          team.officialReviews = value as int;
          break;
        case 'RetainedOfficialReview':
          team.retainedOfficialReview = value == true;
          break;
        case 'UniformColor':
          team.uniformColor = value.toString();
          break;
        case 'Color(operator.fg)':
          team.colorFg = value.toString();
          break;
        case 'Color(operator.bg)':
          team.colorBg = value.toString();
          break;
        case 'Id':
          team.serverId = value.toString();
          break;
      }
    }
  }

  void _updateLabel(String path, dynamic value) {
    final regex = RegExp(r'ScoreBoard\.CurrentGame\.Label\((.+)\)');
    final match = regex.firstMatch(path);
    if (match != null) {
      final labelName = match.group(1)!;
      final labelValue = value.toString();
      switch (labelName) {
        case 'Start':
          labelStart = labelValue;
          break;
        case 'Stop':
          labelStop = labelValue;
          break;
        case 'Timeout':
          labelTimeout = labelValue;
          break;
        case 'Undo':
          labelUndo = labelValue;
          break;
        case 'Replaced':
          labelReplaced = labelValue;
          break;
      }
    }
  }
}

class Clock {
  String name;
  String displayName;
  int time;
  bool running;
  int number;

  Clock({
    required this.name,
    this.displayName = '',
    this.time = 0,
    this.running = false,
    this.number = 0,
  });
}

class Team {
  String id;
  String serverId;
  String name;
  String alternateName;
  String uniformColor;
  String colorFg;
  String colorBg;
  int score;
  int timeouts;
  int officialReviews;
  bool retainedOfficialReview;

  Team({
    required this.id,
    this.serverId = '',
    this.name = 'Team',
    this.alternateName = '',
    this.uniformColor = '',
    this.colorFg = '',
    this.colorBg = '',
    this.score = 0,
    this.timeouts = 3,
    this.officialReviews = 1,
    this.retainedOfficialReview = false,
  });

  String get displayName => alternateName.isNotEmpty ? alternateName : name;
}

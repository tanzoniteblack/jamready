import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Acts as the scoreboard operator/NSO: a second, independent WebSocket
/// connection to the CRG server used to drive game state (start a game, fast
/// forward clocks, confirm the official score) so the [RemoteGameEngine]
/// under test can be exercised as it would be from the app.
class ScoreboardOperatorClient {
  ScoreboardOperatorClient(this._channel);

  final WebSocketChannel _channel;

  static Future<ScoreboardOperatorClient> connect(Uri uri) async {
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return ScoreboardOperatorClient(channel);
  }

  Future<void> startNewGame({
    Duration? timeToDerby,
    String ruleset = 'WFTDARuleset',
  }) async {
    _channel.sink.add(
      jsonEncode({
        'action': 'Register',
        'paths': ['ScoreBoard.CurrentGame.Game'],
      }),
    );
    final message = {
      'action': 'StartNewGame',
      'data': {
        'Team1': '',
        'Team2': '',
        'Ruleset': ruleset,
        'IntermissionClock': timeToDerby != null
            ? '${timeToDerby.inMilliseconds}'
            : null,
        'Advance': false,
        'Points1': 0,
        'Points2': 0,
        'TO1': 0,
        'TO2': 0,
        'OR1': 0,
        'OR2': 0,
        'Period': 0,
        'Jam': 0,
        'PeriodClock': '0',
      },
    };

    _channel.sink.add(jsonEncode(message));
    // give the server a few seconds to actually get going
    await Future.delayed(const Duration(seconds: 2));
  }

  /// Sets a clock time on the server
  void setClockTime(String gameId, String clockName, int timeMs) {
    _channel.sink.add(
      jsonEncode({
        'action': 'Set',
        'key': 'ScoreBoard.Game($gameId).Clock($clockName).Time',
        'value': timeMs.toString(),
        'flag': '',
      }),
    );
  }

  /// Awards [points] to a team's current scoring trip — the same WS key a
  /// real operator's "+4"-style scoring button sends. Only takes effect
  /// while a jam is actually running (`Team.TRIP_SCORE`'s handler in
  /// TeamImpl checks `game.isInJam()`); Team.Score itself is a derived value
  /// computed from trip scores and can't be set directly.
  void addTripScore(String gameId, int teamNumber, int points) {
    _channel.sink.add(
      jsonEncode({
        'action': 'Set',
        'key': 'ScoreBoard.Game($gameId).Team($teamNumber).TripScore',
        'value': points.toString(),
        'flag': '',
      }),
    );
  }

  void disableOfficialScoreRule(String gameId) {
    // v2025.9+ enforces a timing gate (INHIBIT_FINAL_SCORE) before OfficialScore
    // can be set. Disable the rule so tests don't have to wait 30s after final
    // jam end.
    _channel.sink.add(
      jsonEncode({
        'action': 'Set',
        'key': 'ScoreBoard.Game($gameId).Rule(Score.EnforceTimeToOr)',
        'value': 'false',
        'flag': '',
      }),
    );
  }

  void setOfficialScore(String gameId) {
    _channel.sink.add(
      jsonEncode({
        'action': 'Set',
        'key': 'ScoreBoard.Game($gameId).OfficialScore',
        'value': true,
        'flag': '',
      }),
    );
  }

  Future<void> close() async {
    await _channel.sink.close();
  }
}

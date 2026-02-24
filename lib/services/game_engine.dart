import '../models/scoreboard_state.dart';

/// Abstract interface for game control engines.
///
/// Implementations include:
/// - [RemoteGameEngine]: WebSocket-based connection to CRG Scoreboard server
/// - [LocalGameEngine]: Timer-based offline game engine
abstract class GameEngine {
  /// Whether the engine is actively running (connected or game in progress)
  bool get isActive;

  /// The current scoreboard state
  ScoreboardState get state;

  /// Whether this engine supports undo operations
  /// Remote engines support undo, local engines do not
  bool get supportsUndo;

  /// Whether this is a local/offline engine
  bool get isLocal;

  /// Initialize the engine (connect to server or start local timers)
  Future<void> initialize();

  /// Clean up resources (disconnect or stop timers)
  Future<void> dispose();

  /// Start a jam
  void startJam();

  /// Stop the current jam (or end timeout, depending on state)
  void stopJam();

  /// Start a timeout
  void startTimeout();

  /// End the current timeout
  void endTimeout();

  /// Set the timeout owner
  /// [owner] can be '1', '2', or 'O' for official timeout
  /// [isOfficialReview] indicates if this is an official review
  void setTimeoutOwner(String owner, {bool isOfficialReview = false});

  /// Adjust a clock by a delta (in milliseconds)
  /// [clockName] is one of: 'Period', 'Jam', 'Lineup', 'Timeout', 'Intermission'
  /// [deltaMs] is the change amount (can be negative)
  void adjustClock(String clockName, int deltaMs);

  /// Set a clock to an absolute time (in milliseconds)
  /// [clockName] is one of: 'Period', 'Jam', 'Lineup', 'Timeout', 'Intermission'
  /// [timeMs] is the new time value
  void setClockTime(String clockName, int timeMs);

  /// Adjust a team's score (only supported in local mode)
  /// [teamNumber] is 1 or 2
  /// [delta] is the score change (can be negative)
  void adjustScore(int teamNumber, int delta);

  /// Toggle retained official review for a team (only supported in local mode)
  void setRetainedReview(int teamNumber, bool retained);

  /// Undo the last action (if supported)
  void undo();
}

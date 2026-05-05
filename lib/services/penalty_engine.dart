import '../models/penalty_box_state.dart';

/// Abstract interface for penalty box control.
/// Implemented by LocalPenaltyEngine (offline) and RemotePenaltyEngine (CRG).
abstract class PenaltyEngine {
  PenaltyBoxState get state;
  bool get isLocal;

  Future<void> initialize();
  Future<void> dispose();

  /// Called when the user manually toggles the jam (offline mode only).
  void toggleJam();

  /// Reconnect to the remote scoreboard; no-op in local mode.
  Future<void> reconnect();

  /// Report a penalty to CRG (no-op in local mode).
  void reportPenalty({
    required int teamIndex,
    required String skaterNumber,
    required int periodNumber,
    required int jamNumber,
  });
}

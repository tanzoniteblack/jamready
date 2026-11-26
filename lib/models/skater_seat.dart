import 'package:flutter/material.dart';

enum SkaterPosition { jammer, pivot, blocker }

enum AppRole {
  pbm,
  solo,
  team1BlockersOnly,
  team1Full,
  team2Full,
  team2BlockersOnly,
}

enum SeatState { empty, running, paused, standing, done }

/// Whole seconds displayed for [remaining]. Rounded up, matching CRG and the
/// game clocks, so a timer only reads 0:00 once it has actually run out.
int displaySeconds(Duration remaining) => remaining <= Duration.zero
    ? 0
    : (remaining.inMicroseconds / Duration.microsecondsPerSecond).ceil();

/// Formats [remaining] as m:ss using [displaySeconds].
String formatPenaltyTime(Duration remaining) =>
    _formatSeconds(displaySeconds(remaining));

/// Formats [overtime] as a negative m:ss, rounded down like CRG's count-up
/// clocks, so it reads 0:00 until a full second has passed.
String formatOvertime(Duration overtime) {
  final secs = overtime.inSeconds;
  return secs <= 0 ? '0:00' : '-${_formatSeconds(secs)}';
}

String _formatSeconds(int secs) =>
    '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';

class SkaterSeat {
  final String id;
  String skaterNumber;
  SkaterPosition position;
  int teamIndex; // 1 or 2
  Duration timeRemaining;

  // Jam time that has passed since this seat's time ran out without the
  // skater being released.
  Duration overtime;
  bool isRunning;
  bool isInQueue;

  // Whether this skater arrived between jams (affects jammer sync logic)
  bool arrivedBetweenJams;

  // Total penalties being served in this box trip; used for §4.4 jammer sync math
  int penaltyCount;

  // How many of this jammer's penalties have not yet been paired with the
  // opposing jammer in a §4.4 swap. Drives sync math instead of penaltyCount
  // so already-matched penalties are never re-matched.
  int unmatchedPenalties;

  SkaterSeat({
    required this.id,
    this.skaterNumber = '',
    this.position = SkaterPosition.blocker,
    required this.teamIndex,
    this.timeRemaining = Duration.zero,
    this.overtime = Duration.zero,
    this.isRunning = false,
    this.isInQueue = false,
    this.arrivedBetweenJams = false,
    this.penaltyCount = 0,
    this.unmatchedPenalties = 0,
  });

  SeatState get state {
    if (skaterNumber.isEmpty) return SeatState.empty;
    if (timeRemaining <= Duration.zero) return SeatState.done;
    if (!isRunning) return SeatState.paused;
    if (displaySeconds(timeRemaining) <= 10) return SeatState.standing;
    return SeatState.running;
  }

  /// Time shown on the seat: the countdown, or how far past zero it went.
  String get timeLabel => overtime > Duration.zero
      ? formatOvertime(overtime)
      : formatPenaltyTime(timeRemaining);

  bool get isEmpty => skaterNumber.isEmpty;
  bool get isOccupied => !isEmpty;

  Color alertColor(Color teamColor) {
    switch (state) {
      case SeatState.empty:
        return Colors.white12;
      case SeatState.done:
        return Colors.red.shade700;
      case SeatState.standing:
        return Colors.amber.shade600;
      case SeatState.running:
        return Colors.green.shade500;
      case SeatState.paused:
        return Colors.white24;
    }
  }

  void addPenalty() {
    timeRemaining += const Duration(seconds: 30);
    overtime = Duration.zero;
    penaltyCount++;
    unmatchedPenalties++;
  }

  void removePenalty() {
    if (penaltyCount > 1) penaltyCount--;
  }

  void clear() {
    skaterNumber = '';
    timeRemaining = Duration.zero;
    overtime = Duration.zero;
    isRunning = false;
    isInQueue = false;
    arrivedBetweenJams = false;
    penaltyCount = 0;
    unmatchedPenalties = 0;
  }

  void setSkater({
    required String number,
    required SkaterPosition pos,
    bool arrivedBetween = false,
  }) {
    skaterNumber = number;
    position = pos;
    timeRemaining = const Duration(seconds: 30);
    overtime = Duration.zero;
    isRunning = false;
    arrivedBetweenJams = arrivedBetween;
    penaltyCount = 1;
    unmatchedPenalties = 1;
  }

  SkaterSeat copyWith({
    String? skaterNumber,
    SkaterPosition? position,
    int? teamIndex,
    Duration? timeRemaining,
    Duration? overtime,
    bool? isRunning,
    bool? isInQueue,
    bool? arrivedBetweenJams,
    int? penaltyCount,
    int? unmatchedPenalties,
  }) {
    return SkaterSeat(
      id: id,
      skaterNumber: skaterNumber ?? this.skaterNumber,
      position: position ?? this.position,
      teamIndex: teamIndex ?? this.teamIndex,
      timeRemaining: timeRemaining ?? this.timeRemaining,
      overtime: overtime ?? this.overtime,
      isRunning: isRunning ?? this.isRunning,
      isInQueue: isInQueue ?? this.isInQueue,
      arrivedBetweenJams: arrivedBetweenJams ?? this.arrivedBetweenJams,
      penaltyCount: penaltyCount ?? this.penaltyCount,
      unmatchedPenalties: unmatchedPenalties ?? this.unmatchedPenalties,
    );
  }
}

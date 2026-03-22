import 'package:flutter/material.dart';

enum SkaterPosition { jammer, pivot, blocker }

enum AppRole { pbm, boxTimerTeam1, boxTimerTeam2, solo }

enum SeatState { empty, running, paused, standing, done }

class SkaterSeat {
  final String id;
  String skaterNumber;
  SkaterPosition position;
  int teamIndex; // 1 or 2
  Duration timeRemaining;
  bool isRunning;
  bool isFouledOut;
  bool isInQueue;

  // Whether this skater arrived between jams (affects jammer sync logic)
  bool arrivedBetweenJams;

  SkaterSeat({
    required this.id,
    this.skaterNumber = '',
    this.position = SkaterPosition.blocker,
    required this.teamIndex,
    this.timeRemaining = Duration.zero,
    this.isRunning = false,
    this.isFouledOut = false,
    this.isInQueue = false,
    this.arrivedBetweenJams = false,
  });

  SeatState get state {
    if (skaterNumber.isEmpty) return SeatState.empty;
    if (timeRemaining <= Duration.zero) return SeatState.done;
    if (!isRunning) return SeatState.paused;
    if (timeRemaining.inSeconds <= 10) return SeatState.standing;
    return SeatState.running;
  }

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
        return teamColor.withValues(alpha: 0.7);
      case SeatState.paused:
        return Colors.white24;
    }
  }

  void addPenalty() {
    timeRemaining += const Duration(seconds: 30);
    if (isRunning) return; // already running
  }

  void clear() {
    skaterNumber = '';
    position = SkaterPosition.blocker;
    timeRemaining = Duration.zero;
    isRunning = false;
    isFouledOut = false;
    isInQueue = false;
    arrivedBetweenJams = false;
  }

  void setSkater({
    required String number,
    required SkaterPosition pos,
    bool fouledOut = false,
    bool arrivedBetween = false,
  }) {
    skaterNumber = number;
    position = pos;
    timeRemaining = const Duration(seconds: 30);
    isRunning = false;
    isFouledOut = fouledOut;
    arrivedBetweenJams = arrivedBetween;
  }

  SkaterSeat copyWith({
    String? skaterNumber,
    SkaterPosition? position,
    int? teamIndex,
    Duration? timeRemaining,
    bool? isRunning,
    bool? isFouledOut,
    bool? isInQueue,
    bool? arrivedBetweenJams,
  }) {
    return SkaterSeat(
      id: id,
      skaterNumber: skaterNumber ?? this.skaterNumber,
      position: position ?? this.position,
      teamIndex: teamIndex ?? this.teamIndex,
      timeRemaining: timeRemaining ?? this.timeRemaining,
      isRunning: isRunning ?? this.isRunning,
      isFouledOut: isFouledOut ?? this.isFouledOut,
      isInQueue: isInQueue ?? this.isInQueue,
      arrivedBetweenJams: arrivedBetweenJams ?? this.arrivedBetweenJams,
    );
  }
}

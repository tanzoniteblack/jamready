import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import '../models/penalty_box_state.dart';
import '../models/skater_seat.dart';
import '../styles/text_styles.dart';
import 'skater_entry_dialog.dart';

/// Displays a single penalty box seat with countdown timer.
///
/// States:
///   empty        → tap to start anonymous timer + open number dialog
///   running ('?')→ tap to enter skater number
///   running      → ±30s buttons inline
///   standing (≤10s) → amber pulsing
///   done (0:00)  → red pulsing, repeating haptic; tap to clear
///   paused       → time frozen; jammer tap starts timer
class SeatCard extends StatefulWidget {
  final SkaterSeat seat;
  final bool compact;

  const SeatCard({super.key, required this.seat, this.compact = false});

  @override
  State<SeatCard> createState() => _SeatCardState();
}

class _SeatCardState extends State<SeatCard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  SeatState? _lastState;
  Timer? _doneHapticTimer;
  bool _preStandWarnGiven = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _doneHapticTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _onTap(PenaltyBoxState state) {
    final seat = widget.seat;
    switch (seat.state) {
      case SeatState.empty:
        state.startSeatAnonymously(seat);
      case SeatState.done:
        _hapticLight();
        state.clearSeat(seat);
      case SeatState.running:
      case SeatState.standing:
      case SeatState.paused:
        state.toggleSeatTimer(seat);
    }
  }

  void _onNumberTap(PenaltyBoxState state) async {
    final seat = widget.seat;
    if (seat.isEmpty) return;
    await _getSkaterNumber(state);
  }

  void _onLongPress(PenaltyBoxState state) async {
    final seat = widget.seat;
    if (seat.isEmpty) return;
    _hapticMedium();
    await _showAdjustSheet(state);
  }

  Future<void> _getSkaterNumber(PenaltyBoxState state) async {
    final seat = widget.seat;
    final isJammer = seat.position == SkaterPosition.jammer;

    final result = await showSkaterEntryDialog(
      context,
      initialPosition: isJammer ? SkaterPosition.jammer : SkaterPosition.blocker,
      allowJammer: isJammer,
      teamName: state.teamInfo(seat.teamIndex).name,
      barrierDismissible: true,
      knownNumbers: state.knownNumbers(seat.teamIndex),
    );

    if (result != null && mounted) {
      state.setSkaterNumber(seat, result.number, position: result.position);
    }
  }

  Future<void> _showAdjustSheet(PenaltyBoxState state) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1C21),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ChangeNotifierProvider.value(
        value: state,
        child: _SeatAdjustSheet(seat: widget.seat, state: state),
      ),
    );
  }

  void _hapticLight() => Vibration.vibrate(duration: 50);
  void _hapticMedium() => Vibration.vibrate(duration: 150);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PenaltyBoxState>();
    final seat = widget.seat;
    final seatState = seat.state;
    final teamColor = state.teamInfo(seat.teamIndex).color;
    final compact = widget.compact;

    // State transition side-effects
    if (_lastState != seatState) {
      if (seatState == SeatState.standing && _lastState == SeatState.running) {
        Vibration.vibrate(pattern: [0, 100, 80, 100]);
      } else if (seatState == SeatState.done) {
        Vibration.vibrate(duration: 600);
        _doneHapticTimer?.cancel();
        _doneHapticTimer = Timer.periodic(
          const Duration(seconds: 2),
          (_) => Vibration.vibrate(duration: 300),
        );
      } else if (_lastState == SeatState.done) {
        _doneHapticTimer?.cancel();
        _doneHapticTimer = null;
      }
      _lastState = seatState;
    }

    // Pre-warn: light double buzz 1 second before STAND threshold
    if (seatState == SeatState.running && seat.timeRemaining.inSeconds <= 11 && !_preStandWarnGiven) {
      _preStandWarnGiven = true;
      Vibration.vibrate(pattern: [0, 50, 50, 50]);
    }
    // Re-arm when time goes back above threshold (e.g. +30s added) or seat cleared
    if (_preStandWarnGiven && (seatState == SeatState.empty || seat.timeRemaining.inSeconds > 11)) {
      _preStandWarnGiven = false;
    }

    final accentColor = seat.alertColor(teamColor);

    return GestureDetector(
      onTap: () => _onTap(state),
      onLongPress: () => _onLongPress(state),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.12),
          border: Border.all(color: accentColor.withValues(alpha: 0.6), width: 1.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 8 : 12),
          child: seatState == SeatState.empty
              ? _buildEmpty(teamColor, compact)
              : _buildOccupied(context, state, seat, seatState, teamColor, compact),
        ),
      ),
    );
  }

  Widget _buildEmpty(Color teamColor, bool compact) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_circle_outline, color: Colors.white24, size: compact ? 26 : 34),
        const SizedBox(height: 6),
        Text(
          _positionLabel(widget.seat.position),
          style: AppTextStyles.clockLabel.copyWith(
            color: Colors.white24,
            fontSize: compact ? 11 : 13,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildOccupied(
    BuildContext context,
    PenaltyBoxState state,
    SkaterSeat seat,
    SeatState seatState,
    Color teamColor,
    bool compact,
  ) {
    final isStanding = seatState == SeatState.standing;
    final isDone = seatState == SeatState.done;
    final isPaused = seatState == SeatState.paused;
    final isActive = seatState == SeatState.running || isStanding;
    final timeStr = _formatTime(seat.timeRemaining);
    final timerFontSize = compact ? 30.0 : 42.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Row 1: position label (left) + skater number (right)
        Row(
          children: [
            Text(
              _positionLabel(seat.position),
              style: AppTextStyles.clockLabel.copyWith(
                color: teamColor.withValues(alpha: 0.85),
                fontSize: compact ? 10 : 12,
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _onNumberTap(state),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '#${seat.skaterNumber}',
                  style: AppTextStyles.skaterNumber.copyWith(fontSize: compact ? 18 : 22),
                ),
              ),
            ),
          ],
        ),

        // Row 2: timer / done / paused display — fills available space
        Expanded(
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: isDone
                  ? ScaleTransition(
                      scale: _pulseAnimation,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'DONE',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.alertLabel.copyWith(
                              color: Colors.red.shade400,
                              fontSize: compact ? 22 : 28,
                            ),
                          ),
                          Text(
                            'tap to clear',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.clockLabel.copyWith(
                              color: Colors.red.shade300.withValues(alpha: 0.7),
                              fontSize: 11,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    )
                  : isStanding
                      ? ScaleTransition(
                          scale: _pulseAnimation,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timeStr,
                                style: AppTextStyles.clockTimeSmall.copyWith(
                                  color: Colors.amber.shade300,
                                  fontSize: compact ? 28 : 36,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'STAND',
                                style: AppTextStyles.alertLabel.copyWith(
                                  color: Colors.amber.shade400,
                                  fontSize: compact ? 11 : 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : isPaused
                          ? Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  timeStr,
                                  style: AppTextStyles.clockTimeSmall.copyWith(
                                    color: Colors.white38,
                                    fontSize: timerFontSize,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'PAUSED',
                                  style: AppTextStyles.clockLabel.copyWith(
                                    color: Colors.white24,
                                    fontSize: compact ? 10 : 11,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            )
                          : ScaleTransition(
                              scale: _pulseAnimation,
                              child: Text(
                                timeStr,
                                style: AppTextStyles.clockTimeSmall.copyWith(
                                  color: Colors.white,
                                  fontSize: timerFontSize,
                                ),
                              ),
                            ),
            ),
          ),
        ),

        // Row 3: penalty buttons (running or standing only)
        if (isActive)
          Row(
            children: [
              if (seat.penaltyCount > 1)
                _PenaltyButton(
                  label: '−30s',
                  color: Colors.white24,
                  onTap: () => state.removePenaltyFromSeat(seat),
                ),
              const Spacer(),
              _PenaltyButton(
                label: '+30s',
                color: Colors.white24,
                onTap: () => state.addPenaltyToSeat(seat),
              ),
            ],
          ),
      ],
    );
  }

  String _formatTime(Duration d) {
    if (d <= Duration.zero) return '0:00';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _positionLabel(SkaterPosition pos) {
    return switch (pos) {
      SkaterPosition.jammer => 'JAMMER',
      SkaterPosition.pivot => 'PIVOT',
      SkaterPosition.blocker => 'BLOCKER',
    };
  }
}

/// Inline ±30s / ±1s button chip.
class _PenaltyButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _PenaltyButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: enabled ? 0.07 : 0.03),
          border: Border.all(color: enabled ? color : Colors.white12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTextStyles.clockLabel.copyWith(
            color: enabled ? Colors.white54 : Colors.white24,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for fine-tuning a seat's timer and clearing the seat.
class _SeatAdjustSheet extends StatelessWidget {
  final SkaterSeat seat;
  final PenaltyBoxState state;

  const _SeatAdjustSheet({required this.seat, required this.state});

  @override
  Widget build(BuildContext context) {
    // Watch state so timer display updates live
    context.watch<PenaltyBoxState>();

    final m = seat.timeRemaining.inMinutes;
    final s = seat.timeRemaining.inSeconds % 60;
    final timeStr = seat.timeRemaining <= Duration.zero
        ? '0:00'
        : '$m:${s.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Seat info
          Row(
            children: [
              Text(
                _posLabel(seat.position),
                style: AppTextStyles.clockLabel.copyWith(
                  color: Colors.white54,
                  fontSize: 13,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                '#${seat.skaterNumber}',
                style: AppTextStyles.skaterNumber.copyWith(fontSize: 20),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Timer adjustment row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SheetAdjustButton(
                label: '−1s',
                onTap: () => state.adjustTime(seat, const Duration(seconds: -1)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  timeStr,
                  style: AppTextStyles.clockTimeSmall.copyWith(fontSize: 48),
                ),
              ),
              _SheetAdjustButton(
                label: '+1s',
                onTap: () => state.adjustTime(seat, const Duration(seconds: 1)),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Clear button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                state.clearSeat(seat);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: Colors.red.shade300,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'CLEAR SEAT',
                style: AppTextStyles.buttonText.copyWith(
                  color: Colors.red.shade300,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _posLabel(SkaterPosition pos) => switch (pos) {
    SkaterPosition.jammer => 'JAMMER',
    SkaterPosition.pivot => 'PIVOT',
    SkaterPosition.blocker => 'BLOCKER',
  };
}

class _SheetAdjustButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SheetAdjustButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: AppTextStyles.clockLabel.copyWith(
            color: Colors.white70,
            fontSize: 16,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

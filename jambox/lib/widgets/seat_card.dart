import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  int _lastReleaseWarnSecond = -1;

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
      if (seatState == SeatState.done) {
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

    // Stand warn: triple heavy burst at 12s — tell the player to get ready to stand
    if (seatState == SeatState.running && seat.timeRemaining.inSeconds <= 12 && !_preStandWarnGiven) {
      _preStandWarnGiven = true;
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 100), HapticFeedback.heavyImpact);
      Future.delayed(const Duration(milliseconds: 200), HapticFeedback.heavyImpact);
    }
    if (_preStandWarnGiven && (seatState == SeatState.empty || seat.timeRemaining.inSeconds > 12)) {
      _preStandWarnGiven = false;
    }

    // Release warn: rapid quad heavy burst each second at 2s and 1s — fires during standing state
    final secs = seat.timeRemaining.inSeconds;
    final isRunningOrStanding = seatState == SeatState.running || seatState == SeatState.standing;
    if (isRunningOrStanding && secs <= 2 && secs >= 1 && secs != _lastReleaseWarnSecond) {
      _lastReleaseWarnSecond = secs;
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 80), HapticFeedback.heavyImpact);
      Future.delayed(const Duration(milliseconds: 160), HapticFeedback.heavyImpact);
      Future.delayed(const Duration(milliseconds: 240), HapticFeedback.heavyImpact);
    }
    if (_lastReleaseWarnSecond >= 0 && (seatState == SeatState.empty || secs > 2)) {
      _lastReleaseWarnSecond = -1;
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
///
/// The timer display is frozen at the value when the sheet opened so the user
/// can adjust without racing the live countdown. Adjustments accumulate locally
/// and are applied to the running timer in a single call when Done is tapped.
class _SeatAdjustSheet extends StatefulWidget {
  final SkaterSeat seat;
  final PenaltyBoxState state;

  const _SeatAdjustSheet({required this.seat, required this.state});

  @override
  State<_SeatAdjustSheet> createState() => _SeatAdjustSheetState();
}

class _SeatAdjustSheetState extends State<_SeatAdjustSheet> {
  late Duration _displayTime;

  @override
  void initState() {
    super.initState();
    _displayTime = widget.seat.timeRemaining;
  }

  void _adjust(int seconds) {
    setState(() {
      final next = _displayTime + Duration(seconds: seconds);
      _displayTime = next < Duration.zero ? Duration.zero : next;
    });
  }

  void _done(BuildContext context) {
    final delta = _displayTime - widget.seat.timeRemaining;
    if (delta != Duration.zero) {
      widget.state.adjustTime(widget.seat, delta);
    }
    Navigator.of(context).pop();
  }

  String _formatTime(Duration d) {
    if (d <= Duration.zero) return '0:00';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String _posLabel(SkaterPosition pos) => switch (pos) {
    SkaterPosition.jammer => 'JAMMER',
    SkaterPosition.pivot => 'PIVOT',
    SkaterPosition.blocker => 'BLOCKER',
  };

  @override
  Widget build(BuildContext context) {
    final seat = widget.seat;
    final state = widget.state;

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

          // Timer adjustment row (frozen display + local delta)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SheetAdjustButton(label: '−1s', onTap: () => _adjust(-1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _formatTime(_displayTime),
                  style: AppTextStyles.clockTimeSmall.copyWith(fontSize: 48),
                ),
              ),
              _SheetAdjustButton(label: '+1s', onTap: () => _adjust(1)),
            ],
          ),
          const SizedBox(height: 28),

          // Done button — primary action
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => _done(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'DONE',
                style: AppTextStyles.buttonText.copyWith(fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Release skater — destructive secondary action
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: () {
                state.clearSeat(seat);
                Navigator.of(context).pop();
              },
              child: Text(
                'RELEASE SKATER',
                style: AppTextStyles.clockLabel.copyWith(
                  color: Colors.red.shade400,
                  fontSize: 13,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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

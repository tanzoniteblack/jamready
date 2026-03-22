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
///   running      → +30s button inline; no tap action
///   standing (≤10s) → "STAND" cue, amber, pulses
///   done (0:00)  → "DONE" cue, red; tap to clear
///   paused       → time frozen between jams; jammer tap starts timer
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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _onTap(PenaltyBoxState state) async {
    final seat = widget.seat;
    switch (seat.state) {
      case SeatState.empty:
        await _startAnonymousAndGetNumber(state);
      case SeatState.done:
        _hapticLight();
        state.clearSeat(seat);
      case SeatState.running:
      case SeatState.standing:
        // '?' → ask for number; named → no tap action (+30s button handles penalty)
        if (seat.skaterNumber == '?') {
          await _getSkaterNumber(state);
        }
      case SeatState.paused:
        if (seat.position == SkaterPosition.jammer && state.jamRunning) {
          state.startJammerTimer(seat.teamIndex);
        } else if (seat.skaterNumber == '?') {
          await _getSkaterNumber(state);
        }
    }
  }

  void _onLongPress(PenaltyBoxState state) async {
    final seat = widget.seat;
    if (seat.isEmpty) return;
    _hapticMedium();
    final confirmed = await _showClearConfirm();
    if (confirmed == true && mounted) {
      state.clearSeat(seat);
    }
  }

  /// Immediately starts an anonymous timer, then shows a non-blocking number dialog.
  Future<void> _startAnonymousAndGetNumber(PenaltyBoxState state) async {
    final seat = widget.seat;
    final isJammer = seat.position == SkaterPosition.jammer;

    if (!isJammer) {
      final blockers = state.blockerSeats(seat.teamIndex);
      if (blockers.every((s) => s.isOccupied)) {
        await _addToQueue(state);
        return;
      }
    }

    // Start timer immediately with placeholder '?'
    state.startSeatAnonymously(seat);

    if (!mounted) return;

    // Non-blocking: user can dismiss without entering a number
    final result = await showSkaterEntryDialog(
      context,
      initialPosition: isJammer ? SkaterPosition.jammer : SkaterPosition.blocker,
      allowJammer: isJammer,
      teamName: state.teamInfo(seat.teamIndex).name,
      barrierDismissible: true,
    );

    if (result != null && mounted) {
      state.setSkaterNumber(seat, result.number, position: result.position);
    }
  }

  /// Shows number-entry dialog for an already-running anonymous seat.
  Future<void> _getSkaterNumber(PenaltyBoxState state) async {
    final seat = widget.seat;
    final isJammer = seat.position == SkaterPosition.jammer;

    final result = await showSkaterEntryDialog(
      context,
      initialPosition: isJammer ? SkaterPosition.jammer : SkaterPosition.blocker,
      allowJammer: isJammer,
      teamName: state.teamInfo(seat.teamIndex).name,
      barrierDismissible: true,
    );

    if (result != null && mounted) {
      state.setSkaterNumber(seat, result.number, position: result.position);
    }
  }

  Future<void> _addToQueue(PenaltyBoxState state) async {
    final result = await showSkaterEntryDialog(
      context,
      initialPosition: SkaterPosition.blocker,
      allowJammer: false,
      teamName: state.teamInfo(widget.seat.teamIndex).name,
    );
    if (result != null && mounted) {
      state.addToQueue(
        teamIdx: widget.seat.teamIndex,
        number: result.number,
        position: result.position,
      );
    }
  }

  void _addPenalty(BuildContext context, PenaltyBoxState state) {
    _hapticLight();
    state.addPenaltyToSeat(widget.seat);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('+30s penalty added'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () => state.removePenaltyFromSeat(widget.seat),
        ),
      ),
    );
  }

  Future<bool?> _showClearConfirm() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1C21),
        title: Text('Clear Seat?', style: AppTextStyles.clockLabel.copyWith(color: Colors.white, fontSize: 18)),
        content: Text(
          'Remove #${widget.seat.skaterNumber} from the penalty box?',
          style: AppTextStyles.infoText,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('CLEAR', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _hapticLight() {
    Vibration.vibrate(duration: 50);
  }

  void _hapticMedium() {
    Vibration.vibrate(duration: 150);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PenaltyBoxState>();
    final seat = widget.seat;
    final seatState = seat.state;
    final teamColor = state.teamInfo(seat.teamIndex).color;
    final compact = widget.compact;

    // Trigger haptic on state transitions
    if (_lastState != seatState) {
      if (seatState == SeatState.standing && _lastState == SeatState.running) {
        Vibration.vibrate(pattern: [0, 100, 80, 100]);
      } else if (seatState == SeatState.done && _lastState == SeatState.standing) {
        Vibration.vibrate(duration: 500);
      }
      _lastState = seatState;
    }

    final accentColor = seat.alertColor(teamColor);
    final timeStr = _formatTime(seat.timeRemaining);

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
          padding: EdgeInsets.all(compact ? 12 : 16),
          child: seatState == SeatState.empty
              ? _buildEmpty(compact)
              : _buildOccupied(context, state, seat, seatState, timeStr, teamColor, compact),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool compact) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_circle_outline,
          color: Colors.white24,
          size: compact ? 28 : 36,
        ),
        const SizedBox(height: 8),
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
    String timeStr,
    Color teamColor,
    bool compact,
  ) {
    final isStanding = seatState == SeatState.standing;
    final isDone = seatState == SeatState.done;
    final isPaused = seatState == SeatState.paused;
    final isRunningOrStanding = seatState == SeatState.running || isStanding;

    final alertColor = isDone
        ? Colors.red.shade400
        : isStanding
            ? Colors.amber.shade400
            : Colors.white;

    // +30s button anchored to bottom of card via Stack — doesn't push center content
    final addPenaltyButton = !compact && isRunningOrStanding
        ? Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () => _addPenalty(context, state),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '+30s',
                  style: AppTextStyles.clockLabel.copyWith(
                    color: Colors.white54,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          )
        : null;

    final timerContent = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Position label
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _positionLabel(seat.position),
            style: AppTextStyles.clockLabel.copyWith(
              color: teamColor.withValues(alpha: 0.8),
              fontSize: compact ? 11 : 13,
              letterSpacing: 1.5,
            ),
          ),
        ),
        SizedBox(height: compact ? 6 : 8),

        // Skater number
        Text(
          '#${seat.skaterNumber}',
          style: AppTextStyles.skaterNumber.copyWith(
            fontSize: compact ? 28 : 36,
          ),
        ),
        SizedBox(height: compact ? 6 : 8),

        // Timer display
        if (isDone)
          Text(
            'DONE',
            style: AppTextStyles.alertLabel.copyWith(
              color: Colors.red.shade400,
              fontSize: compact ? 20 : 26,
            ),
          )
        else if (isStanding)
          ScaleTransition(
            scale: _pulseAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'STAND',
                  style: AppTextStyles.alertLabel.copyWith(
                    color: Colors.amber.shade400,
                    fontSize: compact ? 16 : 20,
                  ),
                ),
                Text(
                  timeStr,
                  style: AppTextStyles.clockTimeSmall.copyWith(
                    color: alertColor,
                    fontSize: compact ? 32 : 42,
                  ),
                ),
              ],
            ),
          )
        else
          ScaleTransition(
            scale: seat.isRunning ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
            child: Text(
              timeStr,
              style: AppTextStyles.clockTimeSmall.copyWith(
                color: isPaused ? Colors.white38 : Colors.white,
                fontSize: compact ? 36 : 48,
              ),
            ),
          ),

        if (isPaused && !isDone)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'PAUSED',
              style: AppTextStyles.clockLabel.copyWith(
                color: Colors.white38,
                fontSize: 11,
                letterSpacing: 1.5,
              ),
            ),
          ),
      ],
    );

    if (addPenaltyButton == null) return Center(child: timerContent);

    return Stack(
      children: [
        Center(child: timerContent),
        addPenaltyButton,
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
    switch (pos) {
      case SkaterPosition.jammer:
        return 'JAMMER';
      case SkaterPosition.pivot:
        return 'PIVOT';
      case SkaterPosition.blocker:
        return 'BLOCKER';
    }
  }
}

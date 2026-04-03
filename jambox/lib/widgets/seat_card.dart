import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';
import '../models/penalty_box_state.dart';
import '../models/skater_seat.dart';
import '../styles/text_styles.dart';
import 'skater_entry_dialog.dart';

/// Displays a single penalty box seat.
///
/// Always fills its parent — size never changes based on state. The clock is the
/// dominant visual element; everything else is secondary.
///
/// [penaltyOnLeft]: when non-null, penalty buttons are rendered inline with the
/// clock (for compact dual-column layouts). true = +30s on the left (right-column
/// card), false = +30s on the right (left-column card). null = buttons in a row
/// below the clock (single-team / standard view).
class SeatCard extends StatefulWidget {
  final SkaterSeat seat;
  final bool? penaltyOnLeft;

  const SeatCard({super.key, required this.seat, this.penaltyOnLeft});

  @override
  State<SeatCard> createState() => _SeatCardState();
}

class _SeatCardState extends State<SeatCard> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  SeatState? _lastState;
  Timer? _doneHapticTimer;
  Timer? _goFlipTimer;
  bool _showGo = false;
  bool _preStandWarnGiven = false;
  int _lastReleaseWarnSecond = -1;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.93, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _doneHapticTimer?.cancel();
    _goFlipTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startGoFlip() {
    _goFlipTimer?.cancel();
    _goFlipTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (mounted) setState(() => _showGo = !_showGo);
    });
  }

  void _stopGoFlip() {
    _goFlipTimer?.cancel();
    _goFlipTimer = null;
    _showGo = false;
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
    if (widget.seat.isEmpty) return;
    await _getSkaterNumber(state);
  }

  void _onLongPress(PenaltyBoxState state) async {
    if (widget.seat.isEmpty) return;
    _hapticMedium();
    await _showAdjustSheet(state);
  }

  Future<void> _getSkaterNumber(PenaltyBoxState state) async {
    final seat = widget.seat;
    final isJammer = seat.position == SkaterPosition.jammer;
    final result = await showSkaterEntryDialog(
      context,
      initialPosition: isJammer ? SkaterPosition.jammer : SkaterPosition.blocker,
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
    final teamInfo = state.teamInfo(seat.teamIndex);

    // State transition side-effects
    if (_lastState != seatState) {
      if (seatState == SeatState.standing && _lastState == SeatState.running) {
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(milliseconds: 150), HapticFeedback.mediumImpact);
      } else if (seatState == SeatState.done) {
        Vibration.vibrate(duration: 600);
        _doneHapticTimer?.cancel();
        _doneHapticTimer = Timer.periodic(
          const Duration(seconds: 2),
          (_) => Vibration.vibrate(duration: 300),
        );
        _startGoFlip();
      } else if (_lastState == SeatState.done) {
        _doneHapticTimer?.cancel();
        _doneHapticTimer = null;
        _stopGoFlip();
      }
      _lastState = seatState;
    }

    // Pre-stand warn: triple heavy burst at 12s
    if (seatState == SeatState.running && seat.timeRemaining.inSeconds <= 12 && !_preStandWarnGiven) {
      _preStandWarnGiven = true;
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 100), HapticFeedback.heavyImpact);
      Future.delayed(const Duration(milliseconds: 200), HapticFeedback.heavyImpact);
    }
    if (_preStandWarnGiven && (seatState == SeatState.empty || seat.timeRemaining.inSeconds > 12)) {
      _preStandWarnGiven = false;
    }

    // Release warn: quad burst at 1s and 2s remaining
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

    final stateGradientColor = switch (seatState) {
      SeatState.running => const Color(0xFF1A7A36),
      SeatState.standing => Colors.orange.shade700,
      SeatState.done => Colors.red.shade700,
      SeatState.paused => const Color(0xFF135A28),
      SeatState.empty => Colors.transparent,
    };

    return GestureDetector(
      onTap: () => _onTap(state),
      onLongPress: () => _onLongPress(state),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF0E1012),
          gradient: seatState == SeatState.empty
              ? null
              : RadialGradient(
                  colors: [stateGradientColor.withValues(alpha: 0.35), Colors.transparent],
                  radius: 0.85,
                ),
          border: Border.all(
            color: seatState == SeatState.empty
                ? teamInfo.fgColor.withValues(alpha: 0.2)
                : teamInfo.fgColor.withValues(alpha: 0.8),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _buildContent(context, state, seat, seatState, teamInfo),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    PenaltyBoxState state,
    SkaterSeat seat,
    SeatState seatState,
    TeamInfo teamInfo,
  ) {
    final isEmpty = seatState == SeatState.empty;
    final isDone = seatState == SeatState.done ||
        (!isEmpty && seat.timeRemaining <= Duration.zero);
    final isStanding = !isDone && seatState == SeatState.standing;
    final isPaused = seatState == SeatState.paused;
    final isActive = seatState == SeatState.running || isStanding;
    final isInline = widget.penaltyOnLeft != null;
    final canRemove = isActive && seat.penaltyCount > 1;

    final posLabel = seat.position == SkaterPosition.jammer ? 'J' : 'B';
    final timeStr = _formatTime(seat.timeRemaining);

    final clockColor = switch (seatState) {
      SeatState.running => const Color(0xFF4CD97B),
      SeatState.standing => Colors.amber.shade300,
      SeatState.done => Colors.red.shade300,
      SeatState.paused => Colors.white38,
      SeatState.empty => Colors.white24,
    };
    final labelColor = switch (seatState) {
      SeatState.standing => Colors.amber.shade400,
      SeatState.done => Colors.red.shade400,
      _ => Colors.white38,
    };

    // ── Header row: position (left) + number badge (right) ────────────────────
    // Badge is always rendered at the same size (height stability); hidden via
    // Opacity when empty so the layout slot never changes.
    final badgeFontSize = isInline ? 14.0 : 20.0;
    final badgePadH = isInline ? 10.0 : 18.0;
    final badgePadV = isInline ? 6.0 : 10.0;
    final posLabelSize = isInline ? 11.0 : 13.0;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          posLabel,
          style: AppTextStyles.clockLabel.copyWith(
            color: isEmpty ? Colors.white24 : teamInfo.fgColor.withValues(alpha: 0.65),
            fontSize: posLabelSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const Spacer(),
        // Always rendered (height stability) — hidden via Opacity when empty
        Opacity(
          opacity: isEmpty ? 0.0 : 1.0,
          child: IgnorePointer(
            ignoring: isEmpty,
            child: GestureDetector(
              onTap: () => _onNumberTap(state),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: badgePadH, vertical: badgePadV),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#${seat.skaterNumber.isEmpty ? '--' : seat.skaterNumber}',
                  style: AppTextStyles.skaterNumber.copyWith(fontSize: badgeFontSize),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    // ── Clock widget (the main content, sized by FittedBox) ───────────────────
    Widget clockWidget = isDone
        ? ScaleTransition(
            scale: _pulseAnimation,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('0:00', style: AppTextStyles.clockTimeSmall.copyWith(color: clockColor, fontSize: 56)),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 350),
                  child: Text(
                    _showGo ? 'GO' : 'DONE',
                    key: ValueKey(_showGo),
                    style: AppTextStyles.alertLabel.copyWith(color: labelColor, fontSize: 22),
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
                    Text(timeStr, style: AppTextStyles.clockTimeSmall.copyWith(color: clockColor, fontSize: 52)),
                    Text('STAND', style: AppTextStyles.alertLabel.copyWith(color: labelColor, fontSize: 20)),
                  ],
                ),
              )
            : isPaused
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(timeStr, style: AppTextStyles.clockTimeSmall.copyWith(color: clockColor, fontSize: 52)),
                      Text('PAUSED', style: AppTextStyles.clockLabel.copyWith(color: Colors.white38, fontSize: 14, letterSpacing: 2)),
                    ],
                  )
                : ScaleTransition(
                    scale: _pulseAnimation,
                    child: Text(timeStr, style: AppTextStyles.clockTimeSmall.copyWith(color: clockColor, fontSize: 56)),
                  );

    // ── Penalty button builders ───────────────────────────────────────────────
    Widget addBtn(bool show) => Opacity(
      opacity: show ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !show,
        child: _PenaltyButton(label: '+30s', small: isInline, onTap: () => state.addPenaltyToSeat(seat)),
      ),
    );
    Widget removeBtn(bool show) => Opacity(
      opacity: show ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !show,
        child: _PenaltyButton(label: '−30s', small: isInline, onTap: () => state.removePenaltyFromSeat(seat)),
      ),
    );

    // ── Inline layout: penalty buttons flank the clock ────────────────────────
    if (widget.penaltyOnLeft != null) {
      final onLeft = widget.penaltyOnLeft!;
      // onLeft=true (right column): +30s inner-left, clock, −30s outer-right
      // onLeft=false (left column): −30s outer-left, clock, +30s inner-right
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          Expanded(
            child: isEmpty
                ? const Center(child: Icon(Icons.add_circle_outline, color: Colors.white24, size: 32))
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (onLeft) addBtn(isActive) else removeBtn(canRemove),
                      const SizedBox(width: 4),
                      Expanded(child: FittedBox(fit: BoxFit.contain, child: clockWidget)),
                      const SizedBox(width: 4),
                      if (onLeft) removeBtn(canRemove) else addBtn(isActive),
                    ],
                  ),
          ),
        ],
      );
    }

    // ── Standard layout: clock fills Expanded, penalty row pinned below ───────
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: isEmpty
              ? const Center(child: Icon(Icons.add_circle_outline, color: Colors.white24, size: 40))
              : FittedBox(fit: BoxFit.contain, child: clockWidget),
        ),
        // Penalty row always rendered (height stability). Buttons fade in/out.
        Row(
          children: [
            removeBtn(canRemove),
            const Spacer(),
            addBtn(isActive),
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
}

class _PenaltyButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool small;

  const _PenaltyButton({required this.label, required this.onTap, this.small = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: small
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTextStyles.clockLabel.copyWith(
            color: Colors.white54,
            fontSize: small ? 10 : 14,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet for fine-tuning a seat's timer and releasing the skater.
/// The timer display is frozen at the value when the sheet opened.
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
    if (delta != Duration.zero) widget.state.adjustTime(widget.seat, delta);
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
    SkaterPosition.pivot => 'BLOCKER',
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
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),

          Row(
            children: [
              Text(
                _posLabel(seat.position),
                style: AppTextStyles.clockLabel.copyWith(color: Colors.white54, fontSize: 13, letterSpacing: 1.5),
              ),
              const Spacer(),
              Text('#${seat.skaterNumber}', style: AppTextStyles.skaterNumber.copyWith(fontSize: 20)),
            ],
          ),
          const SizedBox(height: 20),

          // Timer display with ±30s and ±1s controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                children: [
                  _SheetAdjustButton(label: '−30s', onTap: () => _adjust(-30)),
                  const SizedBox(height: 6),
                  _SheetAdjustButton(label: '−1s', onTap: () => _adjust(-1)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(_formatTime(_displayTime), style: AppTextStyles.clockTimeSmall.copyWith(fontSize: 48)),
              ),
              Column(
                children: [
                  _SheetAdjustButton(label: '+30s', onTap: () => _adjust(30)),
                  const SizedBox(height: 6),
                  _SheetAdjustButton(label: '+1s', onTap: () => _adjust(1)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: () => _done(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('DONE', style: AppTextStyles.buttonText.copyWith(fontSize: 15)),
            ),
          ),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity, height: 44,
            child: TextButton(
              onPressed: () {
                state.clearSeat(seat);
                Navigator.of(context).pop();
              },
              child: Text(
                'RELEASE SKATER',
                style: AppTextStyles.clockLabel.copyWith(color: Colors.red.shade400, fontSize: 13, letterSpacing: 1.5),
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
          style: AppTextStyles.clockLabel.copyWith(color: Colors.white70, fontSize: 16, letterSpacing: 0.5),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

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
    final isDone = seatState == SeatState.done || (!isEmpty && seat.timeRemaining <= Duration.zero);
    final isStanding = !isDone && seatState == SeatState.standing;
    final hasSecondPenalty = seat.penaltyCount > 1;
    final canToggleSecondPenalty = !isEmpty && (!isDone || hasSecondPenalty);
    final timeStr = _formatTime(seat.timeRemaining);
    final actionLabel = switch (seatState) {
      SeatState.standing => 'STAND',
      SeatState.done => _showGo ? 'GO' : 'DONE',
      SeatState.paused => 'PAUSED',
      SeatState.running => 'SEATED',
      SeatState.empty => 'OPEN',
    };

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
    final isJammer = seat.position == SkaterPosition.jammer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final base = math.min(width, height);
        final horizontalPadding = (width * 0.05).clamp(12.0, 22.0);
        final verticalPadding = (height * 0.08).clamp(12.0, 20.0);
        final topGap = (height * 0.06).clamp(10.0, 18.0);
        final bottomGap = (height * 0.05).clamp(10.0, 16.0);
        final timerFontSize = (math.min(width * 0.34, height * 0.36)).clamp(54.0, 112.0);
        final actionFontSize = (base * 0.12).clamp(16.0, 28.0);
        final emptyIconSize = (base * 0.28).clamp(36.0, 58.0);
        final emptyLabelSize = (base * 0.08).clamp(11.0, 15.0);
        final controlWidth = (width * 0.34).clamp(118.0, 168.0);
        final footerAlignment = widget.penaltyOnLeft == true ? MainAxisAlignment.start : MainAxisAlignment.end;

        Widget timerBlock = isEmpty
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline_rounded, color: Colors.white24, size: emptyIconSize),
                  SizedBox(height: topGap * 0.45),
                  Text(
                    'TAP TO START',
                    style: AppTextStyles.clockLabel.copyWith(
                      color: Colors.white38,
                      fontSize: emptyLabelSize,
                      letterSpacing: 2.2,
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      timeStr,
                      style: AppTextStyles.clockTime.copyWith(
                        color: clockColor,
                        fontSize: timerFontSize,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -3,
                      ),
                    ),
                  ),
                  SizedBox(height: height * 0.015),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      actionLabel,
                      key: ValueKey(actionLabel),
                      style: AppTextStyles.alertLabel.copyWith(
                        color: labelColor,
                        fontSize: actionFontSize,
                        letterSpacing: 2.8,
                      ),
                    ),
                  ),
                ],
              );

        if (isDone || isStanding) {
          timerBlock = ScaleTransition(scale: _pulseAnimation, child: timerBlock);
        } else if (seatState == SeatState.running) {
          timerBlock = FadeTransition(
            opacity: Tween<double>(begin: 0.9, end: 1.0).animate(_pulseAnimation),
            child: timerBlock,
          );
        }

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _SeatRolePill(
                      label: isJammer ? 'JAMMER' : 'BLOCKER',
                      isJammer: isJammer,
                      teamInfo: teamInfo,
                      dimmed: isEmpty,
                    ),
                  ),
                  SizedBox(width: width * 0.03),
                  SizedBox(
                    width: controlWidth,
                    child: _SeatMetaButton(
                      label: isEmpty ? 'SET #' : '#${seat.skaterNumber}',
                      sublabel: isEmpty ? 'player number' : 'edit',
                      onTap: () => _onNumberTap(state),
                      icon: isEmpty ? Icons.edit_outlined : Icons.edit_rounded,
                      active: !isEmpty,
                    ),
                  ),
                ],
              ),
              SizedBox(height: topGap),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width * 0.72),
                    child: timerBlock,
                  ),
                ),
              ),
              SizedBox(height: bottomGap),
              Row(
                mainAxisAlignment: footerAlignment,
                children: [
                  SizedBox(
                    width: controlWidth,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: canToggleSecondPenalty ? 1.0 : 0.35,
                      child: IgnorePointer(
                        ignoring: !canToggleSecondPenalty,
                        child: _SeatMetaButton(
                          label: hasSecondPenalty ? 'UNDO 2ND' : '2ND +30',
                          sublabel: hasSecondPenalty ? '2 penalties' : 'assign second',
                          onTap: () {
                            if (hasSecondPenalty) {
                              state.removePenaltyFromSeat(seat);
                            } else {
                              state.addPenaltyToSeat(seat);
                            }
                          },
                          icon: hasSecondPenalty ? Icons.undo_rounded : Icons.add_rounded,
                          active: hasSecondPenalty,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(Duration d) {
    if (d <= Duration.zero) return '0:00';
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _SeatRolePill extends StatelessWidget {
  final String label;
  final bool isJammer;
  final TeamInfo teamInfo;
  final bool dimmed;

  const _SeatRolePill({
    required this.label,
    required this.isJammer,
    required this.teamInfo,
    required this.dimmed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: teamInfo.bgColor.withValues(alpha: dimmed ? 0.14 : 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: teamInfo.fgColor.withValues(alpha: dimmed ? 0.22 : 0.55),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isJammer) ...[
            Icon(
              Icons.star_rounded,
              size: 18,
              color: teamInfo.fgColor.withValues(alpha: dimmed ? 0.65 : 1),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.clockLabel.copyWith(
                color: teamInfo.fgColor.withValues(alpha: dimmed ? 0.72 : 1),
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeatMetaButton extends StatelessWidget {
  final String label;
  final String sublabel;
  final VoidCallback onTap;
  final IconData icon;
  final bool active;

  const _SeatMetaButton({
    required this.label,
    required this.sublabel,
    required this.onTap,
    required this.icon,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.06),
          border: Border.all(
            color: active ? Colors.white54 : Colors.white24,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.skaterNumber.copyWith(
                      fontSize: 18,
                      color: active ? Colors.white : Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.clockLabel.copyWith(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: 18,
              color: active ? Colors.white : Colors.white54,
            ),
          ],
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

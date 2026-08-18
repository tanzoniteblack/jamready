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

class _SeatCardState extends State<SeatCard>
    with SingleTickerProviderStateMixin {
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
    _pulseAnimation = Tween<double>(begin: 0.93, end: 1.0).animate(
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
      initialPosition: isJammer
          ? SkaterPosition.jammer
          : SkaterPosition.blocker,
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
        Future.delayed(
          const Duration(milliseconds: 150),
          HapticFeedback.mediumImpact,
        );
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

    // Pre-stand warn: triple heavy burst at 12s
    if (seatState == SeatState.running &&
        seat.timeRemaining.inSeconds <= 12 &&
        !_preStandWarnGiven) {
      _preStandWarnGiven = true;
      HapticFeedback.heavyImpact();
      Future.delayed(
        const Duration(milliseconds: 100),
        HapticFeedback.heavyImpact,
      );
      Future.delayed(
        const Duration(milliseconds: 200),
        HapticFeedback.heavyImpact,
      );
    }
    if (_preStandWarnGiven &&
        (seatState == SeatState.empty || seat.timeRemaining.inSeconds > 12)) {
      _preStandWarnGiven = false;
    }

    // Release warn: quad burst at 1s and 2s remaining
    final secs = seat.timeRemaining.inSeconds;
    final isRunningOrStanding =
        seatState == SeatState.running || seatState == SeatState.standing;
    if (isRunningOrStanding &&
        secs <= 2 &&
        secs >= 1 &&
        secs != _lastReleaseWarnSecond) {
      _lastReleaseWarnSecond = secs;
      HapticFeedback.heavyImpact();
      Future.delayed(
        const Duration(milliseconds: 80),
        HapticFeedback.heavyImpact,
      );
      Future.delayed(
        const Duration(milliseconds: 160),
        HapticFeedback.heavyImpact,
      );
      Future.delayed(
        const Duration(milliseconds: 240),
        HapticFeedback.heavyImpact,
      );
    }
    if (_lastReleaseWarnSecond >= 0 &&
        (seatState == SeatState.empty || secs > 2)) {
      _lastReleaseWarnSecond = -1;
    }

    final stateGradientColor = switch (seatState) {
      SeatState.running => const Color(0xFF1A7A36),
      SeatState.standing => Colors.orange.shade700,
      SeatState.done => Colors.red.shade700,
      SeatState.paused => const Color(0xFF135A28),
      SeatState.empty => Colors.transparent,
    };
    final teamSurfaceColor = _teamSurfaceColor(teamInfo);
    final teamAccentColor = _visibleTeamAccent(teamInfo.fgColor, teamInfo);
    final teamHaloColor = _visibleTeamAccent(teamInfo.glowColor, teamInfo);
    final teamRailColor = _visibleTeamAccent(teamInfo.bgColor, teamInfo);
    final isEmpty = seatState == SeatState.empty;
    final teamAlpha = isEmpty ? 0.48 : 0.7;
    final borderAlpha = isEmpty ? 0.48 : 0.92;
    final haloAlpha = isEmpty ? 0.2 : 0.34;

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
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              teamSurfaceColor.withValues(alpha: teamAlpha),
              const Color(0xFF101215),
              const Color(0xFF08090A),
            ],
            stops: const [0, 0.58, 1],
          ),
          border: Border.all(
            color: teamAccentColor.withValues(alpha: borderAlpha),
            width: isEmpty ? 2 : 2.6,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: teamHaloColor.withValues(alpha: haloAlpha),
              blurRadius: isEmpty ? 10 : 16,
              spreadRadius: isEmpty ? 0 : 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.topLeft,
                      radius: 1.05,
                      colors: [
                        teamHaloColor.withValues(alpha: isEmpty ? 0.16 : 0.24),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              if (seatState != SeatState.empty)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        colors: [
                          stateGradientColor.withValues(alpha: 0.28),
                          Colors.transparent,
                        ],
                        radius: 0.82,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: isEmpty ? 7 : 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        teamRailColor.withValues(alpha: isEmpty ? 0.48 : 0.88),
                        teamHaloColor.withValues(alpha: isEmpty ? 0.34 : 0.7),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.16),
                        Colors.black.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                ),
              ),
              _buildContent(context, state, seat, seatState, teamInfo),
            ],
          ),
        ),
      ),
    );
  }

  Color _teamSurfaceColor(TeamInfo teamInfo) {
    final source = teamInfo.bgColor;
    final blend = source.computeLuminance() > 0.65 ? 0.18 : 0.34;
    return Color.lerp(const Color(0xFF0E1012), source, blend)!;
  }

  Color _visibleTeamAccent(Color candidate, TeamInfo teamInfo) {
    if (candidate.computeLuminance() < 0.08) {
      final fallback = teamInfo.glowColor.computeLuminance() > 0.08
          ? teamInfo.glowColor
          : teamInfo.fgColor;
      return Color.lerp(fallback, Colors.white, 0.34)!;
    }
    if (candidate.computeLuminance() > 0.88) {
      return Color.lerp(candidate, const Color(0xFF9DB7FF), 0.18)!;
    }
    return candidate;
  }

  Widget _buildContent(
    BuildContext context,
    PenaltyBoxState state,
    SkaterSeat seat,
    SeatState seatState,
    TeamInfo teamInfo,
  ) {
    final isEmpty = seatState == SeatState.empty;
    final isDone =
        seatState == SeatState.done ||
        (!isEmpty && seat.timeRemaining <= Duration.zero);
    final isStanding = !isDone && seatState == SeatState.standing;
    final hasSecondPenalty = seat.penaltyCount > 1;
    final canToggleSecondPenalty = !isEmpty && (!isDone || hasSecondPenalty);
    final timeStr = isEmpty ? '0:30' : _formatTime(seat.timeRemaining);
    final actionLabel = switch (seatState) {
      SeatState.standing => 'STAND',
      SeatState.done => 'RELEASE',
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
        final shortCard = height < 150;
        final tinyCard = height < 118 || width < 160;
        final padding = (math.min(width, height) * 0.055).clamp(7.0, 14.0);
        final topControlHeight = tinyCard ? 32.0 : 38.0;
        final bottomControlHeight = tinyCard ? 34.0 : 42.0;
        final centerLaneHeight =
            (height -
                    padding * 2 -
                    topControlHeight -
                    bottomControlHeight -
                    (tinyCard ? 4 : 12))
                .clamp(36.0, height);
        final timerFontSize = (math.min(
          width * 0.46,
          centerLaneHeight * (shortCard ? 0.62 : 0.72),
        )).clamp(36.0, 142.0);
        final actionFontSize =
            (math.min(width, height) * (tinyCard ? 0.12 : 0.135)).clamp(
              14.0,
              32.0,
            );
        final numberWidth = (width * 0.34).clamp(70.0, 132.0);
        final penaltyWidth = (width * 0.36).clamp(76.0, 150.0);
        final showTapHint = isEmpty && height >= 132 && width >= 170;

        Widget timerBlock = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                timeStr,
                style: AppTextStyles.clockTime.copyWith(
                  color: clockColor,
                  fontSize: timerFontSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 0.86,
                ),
              ),
            ),
            SizedBox(height: shortCard ? 2 : 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                actionLabel,
                key: ValueKey(actionLabel),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.alertLabel.copyWith(
                  color: labelColor,
                  fontSize: actionFontSize,
                  letterSpacing: 0,
                  height: 0.95,
                ),
              ),
            ),
            if (showTapHint) ...[
              const SizedBox(height: 6),
              Text(
                'TAP START',
                maxLines: 1,
                style: AppTextStyles.clockLabel.copyWith(
                  color: Colors.white38,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        );

        if (isDone || isStanding) {
          timerBlock = ScaleTransition(
            scale: _pulseAnimation,
            child: timerBlock,
          );
        } else if (seatState == SeatState.running) {
          timerBlock = FadeTransition(
            opacity: Tween<double>(
              begin: 0.9,
              end: 1.0,
            ).animate(_pulseAnimation),
            child: timerBlock,
          );
        }

        final secondPenaltyButton = AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: canToggleSecondPenalty ? 1.0 : 0.28,
          child: IgnorePointer(
            ignoring: !canToggleSecondPenalty,
            child: _SecondPenaltyButton(
              compact: tinyCard,
              active: hasSecondPenalty,
              onTap: () {
                if (hasSecondPenalty) {
                  state.removePenaltyFromSeat(seat);
                } else {
                  state.addPenaltyToSeat(seat);
                }
              },
            ),
          ),
        );
        final bottomChildren = <Widget>[
          SizedBox(
            width: penaltyWidth,
            height: bottomControlHeight,
            child: secondPenaltyButton,
          ),
        ];
        if (widget.penaltyOnLeft != true) {
          bottomChildren.insert(0, const Spacer());
        }
        if (widget.penaltyOnLeft == true) bottomChildren.add(const Spacer());

        return Semantics(
          button: true,
          label:
              '${isJammer ? 'Jammer' : 'Blocker'} seat ${seat.skaterNumber.isEmpty ? 'empty' : seat.skaterNumber}, $timeStr, $actionLabel',
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Stack(
              children: [
                Positioned.fill(
                  top: topControlHeight + (tinyCard ? 1 : 4),
                  bottom: bottomControlHeight + (tinyCard ? 1 : 4),
                  child: Center(
                    child: FittedBox(fit: BoxFit.scaleDown, child: timerBlock),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  child: SizedBox(
                    height: topControlHeight,
                    child: _SeatRoleBadge(
                      label: isJammer ? 'J' : 'B',
                      semanticLabel: isJammer ? 'Jammer' : 'Blocker',
                      teamInfo: teamInfo,
                      dimmed: isEmpty,
                      compact: tinyCard,
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: SizedBox(
                    width: numberWidth,
                    height: topControlHeight,
                    child: _NumberButton(
                      label: isEmpty || seat.skaterNumber == '?'
                          ? '#?'
                          : '#${seat.skaterNumber}',
                      onTap: () => _onNumberTap(state),
                      active: !isEmpty && seat.skaterNumber != '?',
                      compact: tinyCard,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: bottomControlHeight,
                    child: Row(children: bottomChildren),
                  ),
                ),
              ],
            ),
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

class _SeatRoleBadge extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final TeamInfo teamInfo;
  final bool dimmed;
  final bool compact;

  const _SeatRoleBadge({
    required this.label,
    required this.semanticLabel,
    required this.teamInfo,
    required this.dimmed,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final size = compact ? 32.0 : 38.0;
    final darkText = teamInfo.fgColor.computeLuminance() < 0.22;
    final fillColor = darkText
        ? Colors.white.withValues(alpha: dimmed ? 0.62 : 0.9)
        : teamInfo.bgColor.withValues(alpha: dimmed ? 0.16 : 0.28);
    final borderColor = darkText
        ? teamInfo.fgColor.withValues(alpha: dimmed ? 0.35 : 0.82)
        : teamInfo.fgColor.withValues(alpha: dimmed ? 0.26 : 0.7);

    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        label: semanticLabel,
        child: Container(
          width: compact ? 44 : 54,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1.4),
          ),
          child: Text(
            label,
            style: AppTextStyles.clockLabel.copyWith(
              color: teamInfo.fgColor.withValues(alpha: dimmed ? 0.72 : 1),
              fontSize: compact ? 17 : 21,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _NumberButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool compact;

  const _NumberButton({
    required this.label,
    required this.onTap,
    this.active = false,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: 'Set player number',
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
          decoration: BoxDecoration(
            color: active
                ? Colors.white.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.07),
            border: Border.all(color: active ? Colors.white60 : Colors.white24),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppTextStyles.skaterNumber.copyWith(
                      fontSize: compact ? 17 : 21,
                      color: active ? Colors.white : Colors.white70,
                      letterSpacing: 0,
                      height: 1,
                    ),
                  ),
                ),
              ),
              SizedBox(width: compact ? 3 : 5),
              Icon(
                Icons.edit_rounded,
                size: compact ? 14 : 16,
                color: active ? Colors.white : Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondPenaltyButton extends StatelessWidget {
  final bool compact;
  final bool active;
  final VoidCallback onTap;

  const _SecondPenaltyButton({
    required this.compact,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = active ? Icons.undo_rounded : Icons.add_rounded;
    final label = active ? 'UNDO' : '+30';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: active ? 'Undo second penalty' : 'Assign second penalty',
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
          decoration: BoxDecoration(
            color: active
                ? Colors.amber.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: active ? Colors.amber.shade300 : Colors.white30,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: compact ? 16 : 18,
                color: active ? Colors.amber.shade200 : Colors.white70,
              ),
              SizedBox(width: compact ? 3 : 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: AppTextStyles.buttonText.copyWith(
                      color: active ? Colors.amber.shade100 : Colors.white,
                      fontSize: compact ? 15 : 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ],
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
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

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
                child: Text(
                  _formatTime(_displayTime),
                  style: AppTextStyles.clockTimeSmall.copyWith(fontSize: 48),
                ),
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
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => _done(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'DONE',
                style: AppTextStyles.buttonText.copyWith(fontSize: 15),
              ),
            ),
          ),
          const SizedBox(height: 12),

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

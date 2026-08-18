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
      SeatState.paused => const Color(0xFF155D8F),
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
      SeatState.paused => const Color(0xFF6CC7FF),
      SeatState.empty => Colors.white24,
    };
    final labelColor = switch (seatState) {
      SeatState.standing => Colors.amber.shade400,
      SeatState.done => Colors.red.shade400,
      SeatState.paused => const Color(0xFF6CC7FF),
      _ => Colors.white38,
    };
    final isJammer = seat.position == SkaterPosition.jammer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final shortCard = height < 150;
        final tinyCard = height < 118 || width < 160;
        final contentPadding = (math.min(width, height) * 0.055).clamp(
          7.0,
          14.0,
        );
        final headerHeight = tinyCard ? 36.0 : 48.0;
        final bodyGap = tinyCard ? 6.0 : 12.0;
        final centerLaneHeight =
            (height - contentPadding * 2 - headerHeight - bodyGap).clamp(
              36.0,
              height,
            );
        final timerFontSize = (math.min(
          width * 0.46,
          centerLaneHeight * (shortCard ? 0.62 : 0.72),
        )).clamp(36.0, 142.0);
        final actionFontSize =
            (math.min(width, height) * (tinyCard ? 0.12 : 0.135)).clamp(
              14.0,
              32.0,
            );
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
              child: seatState == SeatState.paused
                  ? Row(
                      key: const ValueKey('paused'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.pause_circle_filled_rounded,
                          color: labelColor,
                          size: actionFontSize * 0.82,
                        ),
                        SizedBox(width: shortCard ? 4 : 6),
                        Text(
                          actionLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.alertLabel.copyWith(
                            color: labelColor,
                            fontSize: actionFontSize,
                            letterSpacing: 0,
                            height: 0.95,
                          ),
                        ),
                      ],
                    )
                  : Text(
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

        final headerPenaltyControls = AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: canToggleSecondPenalty ? 1.0 : 0.28,
          child: GestureDetector(
            onTap: () {},
            behavior: HitTestBehavior.opaque,
            child: AbsorbPointer(
              absorbing: !canToggleSecondPenalty,
              child: hasSecondPenalty
                  ? Row(
                      children: [
                        Expanded(
                          child: _HeaderPenaltyButton(
                            compact: tinyCard,
                            label: '−30',
                            semanticLabel: 'Remove 30-second penalty',
                            color: Colors.amber.shade100,
                            onTap: () => state.removePenaltyFromSeat(seat),
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                        Expanded(
                          child: _HeaderPenaltyButton(
                            compact: tinyCard,
                            label: '+30',
                            semanticLabel: 'Add 30-second penalty',
                            color: Colors.white,
                            onTap: () => state.addPenaltyToSeat(seat),
                          ),
                        ),
                      ],
                    )
                  : _HeaderPenaltyButton(
                      compact: tinyCard,
                      label: '+30',
                      semanticLabel: 'Add 30-second penalty',
                      color: Colors.white,
                      onTap: () => state.addPenaltyToSeat(seat),
                    ),
            ),
          ),
        );
        return Semantics(
          button: true,
          label:
              '${isJammer ? 'Jammer' : 'Blocker'} seat ${seat.skaterNumber.isEmpty ? 'empty' : seat.skaterNumber}, $timeStr, $actionLabel',
          child: Stack(
            children: [
              // The header is its own edge-to-edge region. It never shares
              // padding or a hit target with the timer action area.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: headerHeight,
                child: _SeatHeader(
                  roleLabel: isJammer ? 'J' : 'B',
                  numberLabel: isEmpty || seat.skaterNumber == '?'
                      ? '#?'
                      : '#${seat.skaterNumber}',
                  onTap: () => _onNumberTap(state),
                  teamInfo: teamInfo,
                  dimmed: isEmpty,
                  compact: tinyCard,
                  penaltyOnLeft: widget.penaltyOnLeft != false,
                  singleColumn: widget.penaltyOnLeft == null,
                  pairedPenaltyControls: hasSecondPenalty,
                  penaltyControls: headerPenaltyControls,
                ),
              ),
              Positioned.fill(
                top: headerHeight + bodyGap,
                bottom: contentPadding,
                child: Center(
                  child: FittedBox(fit: BoxFit.scaleDown, child: timerBlock),
                ),
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

class _SeatHeader extends StatelessWidget {
  final String roleLabel;
  final String numberLabel;
  final VoidCallback onTap;
  final TeamInfo teamInfo;
  final bool dimmed;
  final bool compact;
  final bool penaltyOnLeft;
  final bool singleColumn;
  final bool pairedPenaltyControls;
  final Widget penaltyControls;

  const _SeatHeader({
    required this.roleLabel,
    required this.numberLabel,
    required this.onTap,
    required this.teamInfo,
    required this.dimmed,
    required this.compact,
    required this.penaltyOnLeft,
    required this.singleColumn,
    required this.pairedPenaltyControls,
    required this.penaltyControls,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = teamInfo.fgColor.computeLuminance() < 0.22
        ? Colors.white
        : teamInfo.fgColor;
    final fillColor = Color.lerp(
      const Color(0xFF171A1D),
      teamInfo.bgColor,
      dimmed ? 0.12 : 0.22,
    )!;
    final dividerColor = foreground.withValues(alpha: dimmed ? 0.28 : 0.5);
    final penaltySection = singleColumn
        ? SizedBox(
            width: compact
                ? (pairedPenaltyControls ? 136 : 88)
                : (pairedPenaltyControls ? 176 : 120),
            child: penaltyControls,
          )
        : Expanded(flex: pairedPenaltyControls ? 3 : 2, child: penaltyControls);
    final assignmentSection = Expanded(
      flex: pairedPenaltyControls ? 2 : 3,
      child: _SeatAssignmentBar(
        roleLabel: roleLabel,
        numberLabel: numberLabel,
        onTap: onTap,
        teamInfo: teamInfo,
        dimmed: dimmed,
        compact: compact,
        condensed: pairedPenaltyControls,
      ),
    );
    final divider = VerticalDivider(
      width: 1,
      thickness: 1,
      color: dividerColor,
    );

    return Container(
      decoration: BoxDecoration(
        color: fillColor,
        border: Border(bottom: BorderSide(color: dividerColor, width: 3)),
      ),
      child: Row(
        children: penaltyOnLeft
            ? [penaltySection, divider, assignmentSection]
            : [assignmentSection, divider, penaltySection],
      ),
    );
  }
}

class _SeatAssignmentBar extends StatelessWidget {
  final String roleLabel;
  final String numberLabel;
  final VoidCallback onTap;
  final TeamInfo teamInfo;
  final bool dimmed;
  final bool compact;
  final bool condensed;

  const _SeatAssignmentBar({
    required this.roleLabel,
    required this.numberLabel,
    required this.onTap,
    required this.teamInfo,
    required this.dimmed,
    required this.compact,
    required this.condensed,
  });

  @override
  Widget build(BuildContext context) {
    final useLightText = teamInfo.fgColor.computeLuminance() < 0.22;
    final foreground = useLightText ? Colors.white : teamInfo.fgColor;
    return Tooltip(
      message: 'Set player number',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          button: true,
          label: 'Set $roleLabel player number',
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact || condensed ? 4 : 12,
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Expanded(
                  child: FittedBox(
                    alignment: Alignment.centerLeft,
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          roleLabel,
                          style: AppTextStyles.clockLabel.copyWith(
                            color: foreground.withValues(
                              alpha: dimmed ? 0.72 : 1,
                            ),
                            fontSize: compact || condensed ? 16 : 21,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                            height: 1,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact || condensed ? 3 : 9,
                          ),
                          child: Text(
                            '·',
                            style: AppTextStyles.clockLabel.copyWith(
                              color: foreground.withValues(
                                alpha: dimmed ? 0.45 : 0.7,
                              ),
                              fontSize: compact || condensed ? 16 : 21,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          numberLabel,
                          maxLines: 1,
                          style: AppTextStyles.skaterNumber.copyWith(
                            fontSize: compact || condensed ? 16 : 21,
                            color: foreground.withValues(
                              alpha: dimmed ? 0.72 : 1,
                            ),
                            letterSpacing: 0,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: compact || condensed ? 2 : 6),
                Icon(
                  Icons.edit_rounded,
                  size: compact || condensed ? 12 : 16,
                  color: foreground.withValues(alpha: dimmed ? 0.5 : 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderPenaltyButton extends StatelessWidget {
  final bool compact;
  final String label;
  final String semanticLabel;
  final Color color;
  final VoidCallback onTap;

  const _HeaderPenaltyButton({
    required this.compact,
    required this.label,
    required this.semanticLabel,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: SizedBox.expand(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 10),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: AppTextStyles.buttonText.copyWith(
                    color: color,
                    fontSize: compact ? 15 : 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    height: 1,
                  ),
                ),
              ),
            ),
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

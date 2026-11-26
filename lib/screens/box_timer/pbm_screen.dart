import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/penalty_box_state.dart';
import '../../models/skater_seat.dart';
import '../../services/penalty_engine.dart';
import '../../styles/background.dart';
import '../../styles/text_styles.dart';
import '../../widgets/seat_card.dart';
import 'connection_dot.dart';
import 'jam_status_bar.dart';
import 'shared_helpers.dart';
import 'timer_view_switcher.dart';

/// PBM center view — both teams' jammers side by side.
class PbmScreen extends StatelessWidget {
  final PenaltyEngine engine;
  final ValueChanged<AppRole>? onViewSelected;

  const PbmScreen({super.key, required this.engine, this.onViewSelected});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PenaltyBoxState>();
    final accentColor = _computeAccent(state);

    return DynamicBackground(
      accentColor: accentColor,
      child: PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          appBar: _buildAppBar(context, state, engine),
          body: RefreshIndicator(
            onRefresh: engine.reconnect,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isPortrait =
                    MediaQuery.of(context).orientation == Orientation.portrait;

                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            JamStatusBar(state: state, engine: engine),
                            const SizedBox(height: 16),
                            _BothJammersBanner(state: state),
                            Expanded(
                              child: isPortrait
                                  ? Column(
                                      children: [
                                        Expanded(
                                          child: _PbmTeamColumn(
                                            teamIndex: 1,
                                            state: state,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Expanded(
                                          child: _PbmTeamColumn(
                                            teamIndex: 2,
                                            state: state,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        Expanded(
                                          child: _PbmTeamColumn(
                                            teamIndex: 1,
                                            state: state,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: _PbmTeamColumn(
                                            teamIndex: 2,
                                            state: state,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Color? _computeAccent(PenaltyBoxState state) {
    return computeAccentFromSeats(state.seats);
  }

  AppBar _buildAppBar(
    BuildContext context,
    PenaltyBoxState state,
    PenaltyEngine engine,
  ) {
    return standardAppBar(
      context: context,
      leading: const Icon(Icons.arrow_back, color: Colors.white70),
      title: Row(
        children: [
          Expanded(
            child: TimerViewSwitcher(
              state: state,
              onSelected: onViewSelected ?? state.setTimerView,
            ),
          ),
          const SizedBox(width: 8),
          if (!engine.isLocal)
            Text(
              'P${state.periodNumber}  J${state.jamNumber}',
              style: AppTextStyles.clockLabel.copyWith(fontSize: 14),
            ),
          const SizedBox(width: 8),
          ConnectionDot(state: state),
        ],
      ),
    );
  }
}

class _PbmTeamColumn extends StatelessWidget {
  final int teamIndex;
  final PenaltyBoxState state;

  const _PbmTeamColumn({required this.teamIndex, required this.state});

  @override
  Widget build(BuildContext context) {
    final jammer = state.jammerSeat(teamIndex);
    final teamInfo = state.teamInfo(teamIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildTeamHeader(
          teamInfo.name,
          teamInfo.fgColor,
          teamInfo.bgColor,
          teamInfo.glowColor,
        ),
        const SizedBox(height: 10),
        Expanded(child: SeatCard(seat: jammer)),
      ],
    );
  }
}

/// Full-width banner shown while both jammers are serving time at once. It
/// says why (no swap applies) and who leaves first, so the PBM can see the
/// app expects both to be sitting.
class _BothJammersBanner extends StatelessWidget {
  final PenaltyBoxState state;

  const _BothJammersBanner({required this.state});

  String _jammerName(SkaterSeat seat) {
    final number = state.displayNumber(seat);
    return number == null || number.isEmpty || number == '?'
        ? state.teamInfo(seat.teamIndex).name.toUpperCase()
        : '#$number';
  }

  @override
  Widget build(BuildContext context) {
    final firstOut = state.firstJammerOut;
    final textStyle = AppTextStyles.alertLabel.copyWith(
      color: Colors.white,
      fontSize: 18,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
      height: 1.1,
    );
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: firstOut == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: bothJammersColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.link_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NO SWAP — BOTH JAMMERS SERVE',
                            style: textStyle,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_jammerName(firstOut)} OUT FIRST IN '
                            '${formatPenaltyTime(firstOut.timeRemaining)}',
                            style: textStyle.copyWith(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

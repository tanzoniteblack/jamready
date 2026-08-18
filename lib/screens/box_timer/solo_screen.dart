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

/// Solo view — all seats for both teams.
class SoloScreen extends StatelessWidget {
  final PenaltyEngine engine;
  final ValueChanged<AppRole>? onViewSelected;

  const SoloScreen({super.key, required this.engine, this.onViewSelected});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PenaltyBoxState>();

    return DynamicBackground(
      accentColor: null,
      child: PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          appBar: _buildAppBar(context, state, engine),
          body: RefreshIndicator(
            onRefresh: engine.reconnect,
            child: OrientationBuilder(
              builder: (ctx, orientation) {
                final isLandscape = orientation == Orientation.landscape;
                final teamGap = isLandscape ? 16.0 : 10.0;

                return LayoutBuilder(
                  builder: (ctx2, constraints) => SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SizedBox(
                      height: constraints.maxHeight,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              JamStatusBar(state: state, engine: engine),
                              const SizedBox(height: 10),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _SoloTeamColumn(
                                        teamIndex: 1,
                                        state: state,
                                        landscape: isLandscape,
                                        teamGap: teamGap,
                                      ),
                                    ),
                                    SizedBox(width: teamGap),
                                    Expanded(
                                      child: _SoloTeamColumn(
                                        teamIndex: 2,
                                        state: state,
                                        landscape: isLandscape,
                                        teamGap: teamGap,
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
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
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

class _SoloTeamColumn extends StatelessWidget {
  final int teamIndex;
  final PenaltyBoxState state;
  final bool landscape;
  final double teamGap;

  const _SoloTeamColumn({
    required this.teamIndex,
    required this.state,
    this.landscape = false,
    required this.teamGap,
  });

  @override
  Widget build(BuildContext context) {
    final jammer = state.jammerSeat(teamIndex);
    final blockers = state.blockerSeats(teamIndex);
    final teamInfo = state.teamInfo(teamIndex);
    final header = buildTeamHeader(
      teamInfo.name,
      teamInfo.fgColor,
      teamInfo.bgColor,
      teamInfo.glowColor,
    );

    // Team 1 is always the left column: penalty button goes on the right (inside edge).
    // Team 2 is always the right column: penalty button goes on the left (inside edge).
    final penaltyOnLeft = teamIndex == 2;

    final rowGap = landscape ? 8.0 : 6.0;
    final columnGap = landscape ? 8.0 : 6.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        SizedBox(height: rowGap),
        if (landscape) ...[
          Expanded(
            child: SeatCard(seat: jammer, penaltyOnLeft: penaltyOnLeft),
          ),
          SizedBox(height: rowGap),
          _buildSharedDivider(teamInfo.glowColor),
          SizedBox(height: rowGap),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: SeatCard(
                    seat: blockers[0],
                    penaltyOnLeft: penaltyOnLeft,
                  ),
                ),
                SizedBox(width: columnGap),
                Expanded(
                  child: SeatCard(
                    seat: blockers[1],
                    penaltyOnLeft: penaltyOnLeft,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: rowGap),
          Expanded(
            child: SeatCard(seat: blockers[2], penaltyOnLeft: penaltyOnLeft),
          ),
        ] else ...[
          Expanded(
            child: SeatCard(seat: jammer, penaltyOnLeft: penaltyOnLeft),
          ),
          SizedBox(height: rowGap),
          _buildSharedDivider(teamInfo.glowColor),
          SizedBox(height: rowGap),
          Expanded(
            child: SeatCard(seat: blockers[0], penaltyOnLeft: penaltyOnLeft),
          ),
          SizedBox(height: rowGap),
          Expanded(
            child: SeatCard(seat: blockers[1], penaltyOnLeft: penaltyOnLeft),
          ),
          SizedBox(height: rowGap),
          Expanded(
            child: SeatCard(seat: blockers[2], penaltyOnLeft: penaltyOnLeft),
          ),
        ],
      ],
    );
  }

  Widget _buildSharedDivider(Color color) {
    final extension = teamGap / 2;
    return SizedBox(
      height: jammerBlockerDividerHeight,
      child: LayoutBuilder(
        builder: (context, constraints) => Transform.translate(
          offset: Offset(teamIndex == 1 ? 0 : -extension, 0),
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: constraints.maxWidth + extension,
            maxWidth: constraints.maxWidth + extension,
            child: SizedBox(
              width: constraints.maxWidth + extension,
              child: buildJammerBlockerDivider(color),
            ),
          ),
        ),
      ),
    );
  }
}

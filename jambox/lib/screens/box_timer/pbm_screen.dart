import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/penalty_box_state.dart';
import '../../services/penalty_engine.dart';
import '../../styles/background.dart';
import '../../styles/text_styles.dart';
import '../../widgets/seat_card.dart';
import 'connection_dot.dart';
import 'jam_status_bar.dart';
import 'shared_helpers.dart';

/// PBM center view — both teams' jammers side by side.
class PbmScreen extends StatelessWidget {
  final PenaltyEngine engine;

  const PbmScreen({super.key, required this.engine});

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
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          JamStatusBar(state: state, engine: engine),
                          const SizedBox(height: 16),
                          Expanded(
                            child: MediaQuery.of(context).orientation == Orientation.portrait
                                ? Column(
                                    children: [
                                      Expanded(child: _PbmTeamColumn(teamIndex: 1, state: state)),
                                      const SizedBox(height: 12),
                                      Expanded(child: _PbmTeamColumn(teamIndex: 2, state: state)),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(child: _PbmTeamColumn(teamIndex: 1, state: state)),
                                      const SizedBox(width: 16),
                                      Expanded(child: _PbmTeamColumn(teamIndex: 2, state: state)),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color? _computeAccent(PenaltyBoxState state) {
    return computeAccentFromSeats(state.seats);
  }

  AppBar _buildAppBar(BuildContext context, PenaltyBoxState state, PenaltyEngine engine) {
    return standardAppBar(
      context: context,
      leading: const Icon(Icons.arrow_back, color: Colors.white70),
      title: Row(
        children: [
          Text('JAMBOX', style: AppTextStyles.appBarTitle),
          const Spacer(),
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
        buildTeamHeader(teamInfo.name, teamInfo.fgColor, teamInfo.bgColor, teamInfo.glowColor),
        const SizedBox(height: 10),
        Expanded(child: SeatCard(seat: jammer)),
      ],
    );
  }
}

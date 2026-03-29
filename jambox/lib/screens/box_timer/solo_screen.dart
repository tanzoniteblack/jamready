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

/// Solo view — all seats for both teams.
class SoloScreen extends StatelessWidget {
  final PenaltyEngine engine;

  const SoloScreen({super.key, required this.engine});

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
            child: OrientationBuilder(
              builder: (ctx, orientation) {
                final isLandscape = orientation == Orientation.landscape;
                if (isLandscape) {
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                JamStatusBar(state: state, engine: engine),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(child: _SoloTeamColumn(teamIndex: 1, state: state, landscape: true)),
                                      const SizedBox(width: 24),
                                      Expanded(child: _SoloTeamColumn(teamIndex: 2, state: state, landscape: true)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }
                // Portrait: single outer scroll, AspectRatio cards keep columns equal height
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          JamStatusBar(state: state, engine: engine),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: _SoloTeamColumn(teamIndex: 1, state: state)),
                              const SizedBox(width: 24),
                              Expanded(child: _SoloTeamColumn(teamIndex: 2, state: state)),
                            ],
                          ),
                        ],
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

class _SoloTeamColumn extends StatelessWidget {
  final int teamIndex;
  final PenaltyBoxState state;
  final bool landscape;

  const _SoloTeamColumn({required this.teamIndex, required this.state, this.landscape = false});

  @override
  Widget build(BuildContext context) {
    final jammer = state.jammerSeat(teamIndex);
    final blockers = state.blockerSeats(teamIndex);
    final teamInfo = state.teamInfo(teamIndex);
    final header = buildTeamHeader(teamInfo.name, teamInfo.color);

    if (landscape) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 8),
          Expanded(child: SeatCard(seat: jammer)),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(child: SeatCard(seat: blockers[0], compact: true)),
                const SizedBox(width: 8),
                Expanded(child: SeatCard(seat: blockers[1], compact: true)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: SeatCard(seat: blockers[2], compact: true)),
        ],
      );
    }

    // Portrait: AspectRatio cards so both columns have equal natural height
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: 8),
        AspectRatio(aspectRatio: 1.0, child: SeatCard(seat: jammer)),
        const SizedBox(height: 8),
        AspectRatio(aspectRatio: 1.6, child: SeatCard(seat: blockers[0], compact: true)),
        const SizedBox(height: 8),
        AspectRatio(aspectRatio: 1.6, child: SeatCard(seat: blockers[1], compact: true)),
        const SizedBox(height: 8),
        AspectRatio(aspectRatio: 1.6, child: SeatCard(seat: blockers[2], compact: true)),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/penalty_box_state.dart';
import '../models/skater_seat.dart';
import '../services/penalty_engine.dart';
import '../styles/background.dart';
import '../styles/text_styles.dart';
import '../widgets/seat_card.dart';
import 'box_timer/connection_dot.dart';
import 'box_timer/jam_status_bar.dart';
import 'box_timer/shared_helpers.dart';
import 'box_timer/team_color_picker.dart';

// Re-export screens for convenience
export 'box_timer/pbm_screen.dart';
export 'box_timer/solo_screen.dart';

/// Single-team box timer view.
/// Shows one team's jammer (inner) seat and blocker (outer) seats stacked vertically.
class BoxTimerScreen extends StatefulWidget {
  final PenaltyEngine engine;

  const BoxTimerScreen({super.key, required this.engine});

  @override
  State<BoxTimerScreen> createState() => _BoxTimerScreenState();
}

class _BoxTimerScreenState extends State<BoxTimerScreen> {
  final ScrollController _scrollController = ScrollController();
  double _dragStart = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PenaltyBoxState>();
    final teamIdx = state.teamIndex ?? 1;
    final teamInfo = state.teamInfo(teamIdx);
    final blockers = state.blockerSeats(teamIdx);
    final jammer = state.jammerSeat(teamIdx);
    final showJammer =
        state.role == AppRole.team1Full || state.role == AppRole.team2Full;

    return DynamicBackground(
      accentColor: null,
      child: PopScope(
        canPop: true,
        child: GestureDetector(
          onVerticalDragStart: (details) {
            _dragStart = details.globalPosition.dy;
          },
          onVerticalDragUpdate: (details) {
            // Only handle swipe when scroll is at the top
            if (_scrollController.hasClients && _scrollController.offset <= 0) {
              final delta = details.globalPosition.dy - _dragStart;
              if (delta > 100) {
                Navigator.of(context).pop();
              }
            }
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            appBar: _buildAppBar(context, state, teamInfo, widget.engine),
            body: RefreshIndicator(
              onRefresh: widget.engine.reconnect,
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child:
                            MediaQuery.of(context).orientation ==
                                Orientation.landscape
                            ? _buildLandscape(jammer, blockers, showJammer)
                            : _buildPortrait(
                                jammer,
                                blockers,
                                state,
                                showJammer,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortrait(
    SkaterSeat jammer,
    List<SkaterSeat> blockers,
    PenaltyBoxState state,
    bool showJammer,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JamStatusBar(state: state, engine: widget.engine),
        const SizedBox(height: 16),
        if (showJammer) ...[
          Expanded(child: SeatCard(seat: jammer)),
          const SizedBox(height: 8),
          Expanded(child: SeatCard(seat: blockers[0])),
          const SizedBox(height: 8),
          Expanded(child: SeatCard(seat: blockers[1])),
          const SizedBox(height: 8),
          Expanded(child: SeatCard(seat: blockers[2])),
        ] else
          Expanded(child: buildBlockerStack(blockers)),
      ],
    );
  }

  Widget _buildLandscape(
    SkaterSeat jammer,
    List<SkaterSeat> blockers,
    bool showJammer,
  ) {
    if (!showJammer) {
      return Row(
        children: [
          Expanded(child: SeatCard(seat: blockers[0])),
          const SizedBox(width: 8),
          Expanded(child: SeatCard(seat: blockers[1])),
          const SizedBox(width: 8),
          Expanded(child: SeatCard(seat: blockers[2])),
        ],
      );
    }

    // Full layout: jammer + blockers in uniform 2x2 grid
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: SeatCard(seat: jammer)),
              const SizedBox(width: 8),
              Expanded(child: SeatCard(seat: blockers[0])),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              Expanded(child: SeatCard(seat: blockers[1])),
              const SizedBox(width: 8),
              Expanded(child: SeatCard(seat: blockers[2])),
            ],
          ),
        ),
      ],
    );
  }

  AppBar _buildAppBar(
    BuildContext context,
    PenaltyBoxState state,
    TeamInfo teamInfo,
    PenaltyEngine engine,
  ) {
    final darkTeamText = teamInfo.fgColor.computeLuminance() < 0.22;

    return standardAppBar(
      context: context,
      leading: const Icon(Icons.arrow_back, color: Colors.white70),
      title: Row(
        children: [
          GestureDetector(
            onTap: engine.isLocal
                ? () => _showColorPicker(context, state, teamInfo.index)
                : null,
            child: Container(
              width: 10,
              height: 10,
              decoration: colorSwatchDecoration(
                teamInfo.bgColor,
                glowColor: teamInfo.glowColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: darkTeamText
                ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
                : EdgeInsets.zero,
            decoration: BoxDecoration(
              color: darkTeamText
                  ? Colors.white.withValues(alpha: 0.9)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              teamInfo.name.toUpperCase(),
              style: AppTextStyles.appBarTitle.copyWith(
                color: teamInfo.fgColor,
                shadows: darkTeamText
                    ? []
                    : [
                        Shadow(
                          color: teamInfo.glowColor.withValues(alpha: 0.8),
                          blurRadius: 8,
                        ),
                      ],
              ),
            ),
          ),
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

  void _showColorPicker(
    BuildContext context,
    PenaltyBoxState state,
    int teamIdx,
  ) {
    showDialog<Color>(
      context: context,
      builder: (_) =>
          TeamColorPickerDialog(currentColor: state.teamInfo(teamIdx).color),
    ).then((color) {
      if (color != null) state.setTeamColor(teamIdx, color);
    });
  }
}

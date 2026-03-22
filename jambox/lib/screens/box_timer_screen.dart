import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/penalty_box_state.dart';
import '../models/skater_seat.dart';
import '../services/penalty_engine.dart';
import '../styles/background.dart';
import '../styles/text_styles.dart';
import '../widgets/seat_card.dart';
import '../widgets/queue_panel.dart';

/// Single-team box timer view.
/// Shows one team's jammer (inner) seat and up to 2 blocker (outer) seats.
class BoxTimerScreen extends StatelessWidget {
  final PenaltyEngine engine;

  const BoxTimerScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PenaltyBoxState>();
    final teamIdx = state.teamIndex ?? 1;
    final teamInfo = state.teamInfo(teamIdx);
    final blockers = state.blockerSeats(teamIdx);
    final jammer = state.jammerSeat(teamIdx);

    final accentColor = _computeAccent(state, teamIdx);

    return DynamicBackground(
      accentColor: accentColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(context, state, teamInfo, engine),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Jam status bar
                _JamStatusBar(state: state, engine: engine),
                const SizedBox(height: 16),

                // Jammer seat (inner) — prominent
                Expanded(
                  flex: 5,
                  child: SeatCard(seat: jammer),
                ),
                const SizedBox(height: 12),

                // Blocker seats (outer) — side by side
                Expanded(
                  flex: 4,
                  child: Row(
                    children: [
                      Expanded(child: SeatCard(seat: blockers[0], compact: true)),
                      const SizedBox(width: 10),
                      Expanded(child: SeatCard(seat: blockers[1], compact: true)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Queue panel
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: QueuePanel(teamIndex: teamIdx, compact: true),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color? _computeAccent(PenaltyBoxState state, int teamIdx) {
    final seats = [state.jammerSeat(teamIdx), ...state.blockerSeats(teamIdx)];
    final teamColor = state.teamInfo(teamIdx).color;
    if (seats.any((s) => s.state == SeatState.done)) return Colors.red.shade700;
    if (seats.any((s) => s.state == SeatState.standing)) return Colors.amber.shade600;
    if (seats.any((s) => s.state == SeatState.running)) return teamColor;
    return null;
  }

  AppBar _buildAppBar(
    BuildContext context,
    PenaltyBoxState state,
    TeamInfo teamInfo,
    PenaltyEngine engine,
  ) {
    return AppBar(
      toolbarHeight: 60,
      titleSpacing: 16,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: teamInfo.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            teamInfo.name.toUpperCase(),
            style: AppTextStyles.appBarTitle,
          ),
          const Spacer(),
          Text(
            'P${state.periodNumber}  J${state.jamNumber}',
            style: AppTextStyles.clockLabel.copyWith(fontSize: 14),
          ),
          const SizedBox(width: 8),
          _ConnectionDot(state: state),
        ],
      ),
      flexibleSpace: Align(
        alignment: Alignment.bottomCenter,
        child: Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white70),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

/// PBM center view — two jammers side by side.
class PbmScreen extends StatelessWidget {
  final PenaltyEngine engine;

  const PbmScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PenaltyBoxState>();
    final accentColor = _computeAccent(state);

    return DynamicBackground(
      accentColor: accentColor,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(context, state, engine),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _JamStatusBar(state: state, engine: engine),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    children: [
                      // Team 1 column
                      Expanded(
                        child: _TeamColumn(teamIndex: 1, state: state),
                      ),
                      const SizedBox(width: 16),
                      // Team 2 column
                      Expanded(
                        child: _TeamColumn(teamIndex: 2, state: state),
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
  }

  Color? _computeAccent(PenaltyBoxState state) {
    final allSeats = state.seats;
    if (allSeats.any((s) => s.state == SeatState.done)) return Colors.red.shade700;
    if (allSeats.any((s) => s.state == SeatState.standing)) return Colors.amber.shade600;
    return null;
  }

  AppBar _buildAppBar(BuildContext context, PenaltyBoxState state, PenaltyEngine engine) {
    return AppBar(
      toolbarHeight: 60,
      titleSpacing: 16,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        children: [
          Text('JAMBOX', style: AppTextStyles.appBarTitle),
          const Spacer(),
          Text(
            'P${state.periodNumber}  J${state.jamNumber}',
            style: AppTextStyles.clockLabel.copyWith(fontSize: 14),
          ),
          const SizedBox(width: 8),
          _ConnectionDot(state: state),
        ],
      ),
      flexibleSpace: Align(
        alignment: Alignment.bottomCenter,
        child: Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white70),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  final int teamIndex;
  final PenaltyBoxState state;

  const _TeamColumn({required this.teamIndex, required this.state});

  @override
  Widget build(BuildContext context) {
    final jammer = state.jammerSeat(teamIndex);
    final teamInfo = state.teamInfo(teamIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Team header
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: teamInfo.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                teamInfo.name,
                style: AppTextStyles.clockLabel.copyWith(
                  color: teamInfo.color,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Jammer seat
        Expanded(
          flex: 5,
          child: SeatCard(seat: jammer),
        ),
        const SizedBox(height: 8),

        // Queue
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: QueuePanel(teamIndex: teamIndex, compact: true),
        ),
      ],
    );
  }
}

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
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: _buildAppBar(context, state, engine),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _JamStatusBar(state: state, engine: engine),
                const SizedBox(height: 12),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _SoloTeamColumn(teamIndex: 1, state: state)),
                      const SizedBox(width: 12),
                      Expanded(child: _SoloTeamColumn(teamIndex: 2, state: state)),
                    ],
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
    if (state.seats.any((s) => s.state == SeatState.done)) return Colors.red.shade700;
    if (state.seats.any((s) => s.state == SeatState.standing)) return Colors.amber.shade600;
    return null;
  }

  AppBar _buildAppBar(BuildContext context, PenaltyBoxState state, PenaltyEngine engine) {
    return AppBar(
      toolbarHeight: 60,
      titleSpacing: 16,
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        children: [
          Text('JAMBOX', style: AppTextStyles.appBarTitle),
          const Spacer(),
          Text(
            'P${state.periodNumber}  J${state.jamNumber}',
            style: AppTextStyles.clockLabel.copyWith(fontSize: 14),
          ),
          const SizedBox(width: 8),
          _ConnectionDot(state: state),
        ],
      ),
      flexibleSpace: Align(
        alignment: Alignment.bottomCenter,
        child: Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white70),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _SoloTeamColumn extends StatelessWidget {
  final int teamIndex;
  final PenaltyBoxState state;

  const _SoloTeamColumn({required this.teamIndex, required this.state});

  @override
  Widget build(BuildContext context) {
    final jammer = state.jammerSeat(teamIndex);
    final blockers = state.blockerSeats(teamIndex);
    final teamInfo = state.teamInfo(teamIndex);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: teamInfo.color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  teamInfo.name,
                  style: AppTextStyles.clockLabel.copyWith(
                    color: teamInfo.color,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AspectRatio(aspectRatio: 1.0, child: SeatCard(seat: jammer)),
          const SizedBox(height: 8),
          AspectRatio(aspectRatio: 1.6, child: SeatCard(seat: blockers[0], compact: true)),
          const SizedBox(height: 8),
          AspectRatio(aspectRatio: 1.6, child: SeatCard(seat: blockers[1], compact: true)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: QueuePanel(teamIndex: teamIndex, compact: true),
          ),
        ],
      ),
    );
  }
}

/// Shared jam status bar shown across all game screens.
class _JamStatusBar extends StatelessWidget {
  final PenaltyBoxState state;
  final PenaltyEngine engine;

  const _JamStatusBar({required this.state, required this.engine});

  @override
  Widget build(BuildContext context) {
    final running = state.jamRunning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: running
            ? Colors.green.shade900.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: running ? Colors.green.shade700.withValues(alpha: 0.6) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: running ? Colors.greenAccent : Colors.white24,
              shape: BoxShape.circle,
              boxShadow: running
                  ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.6), blurRadius: 8)]
                  : [],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            running ? 'JAM RUNNING' : 'BETWEEN JAMS',
            style: AppTextStyles.clockLabel.copyWith(
              color: running ? Colors.greenAccent : Colors.white38,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          // Manual jam toggle for offline/local mode
          if (engine.isLocal)
            TextButton(
              onPressed: engine.toggleJam,
              style: TextButton.styleFrom(
                backgroundColor: running
                    ? Colors.red.withValues(alpha: 0.15)
                    : Colors.green.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                running ? 'END JAM' : 'START JAM',
                style: AppTextStyles.buttonText.copyWith(
                  fontSize: 13,
                  color: running ? Colors.red.shade300 : Colors.green.shade300,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  final PenaltyBoxState state;

  const _ConnectionDot({required this.state});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (state.connectionStatus) {
      case ConnectionStatus.connected:
        color = Colors.greenAccent;
      case ConnectionStatus.connecting:
        color = Colors.amber;
      case ConnectionStatus.disconnected:
        color = Colors.white24;
    }
    return Tooltip(
      message: state.connectionMessage,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

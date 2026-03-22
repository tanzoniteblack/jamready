import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/penalty_box_state.dart';
import '../models/skater_seat.dart';
import '../services/penalty_engine.dart';
import '../styles/background.dart';
import '../styles/text_styles.dart';
import '../widgets/seat_card.dart';
import '../widgets/queue_panel.dart';
import 'home_screen.dart';

/// Single-team box timer view.
/// Shows one team's jammer (inner) seat and two blocker (outer) seats stacked vertically.
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
        resizeToAvoidBottomInset: false,
        appBar: _buildAppBar(context, state, teamInfo, engine),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Jam status bar
                _JamStatusBar(state: state, engine: engine),
                const SizedBox(height: 16),

                // Jammer seat — prominent, full width
                Expanded(
                  flex: 5,
                  child: SeatCard(seat: jammer),
                ),
                const SizedBox(height: 12),

                // Bug 3: Blocker seats stacked vertically (full width each)
                Expanded(
                  flex: 3,
                  child: SeatCard(seat: blockers[0], compact: true),
                ),
                const SizedBox(height: 10),
                Expanded(
                  flex: 3,
                  child: SeatCard(seat: blockers[1], compact: true),
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
          // Bug 11: tappable color dot in local mode
          GestureDetector(
            onTap: engine.isLocal ? () => _showColorPicker(context, state, teamInfo.index) : null,
            child: Container(
              width: 10,
              height: 10,
              decoration: _colorSwatchDecoration(teamInfo.color),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            teamInfo.name.toUpperCase(),
            style: AppTextStyles.appBarTitle,
          ),
          const Spacer(),
          // Bug 6: hide P/J counter in local mode
          if (!engine.isLocal)
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
      // Bug 1: back button disposes engine and replaces with HomeScreen
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white70),
        onPressed: () => _navigateBack(context, engine),
      ),
    );
  }

  void _showColorPicker(BuildContext context, PenaltyBoxState state, int teamIdx) {
    showDialog<Color>(
      context: context,
      builder: (_) => _TeamColorPickerDialog(currentColor: state.teamInfo(teamIdx).color),
    ).then((color) {
      if (color != null) state.setTeamColor(teamIdx, color);
    });
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
        resizeToAvoidBottomInset: false,
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
                      Expanded(
                        child: _TeamColumn(teamIndex: 1, state: state),
                      ),
                      const SizedBox(width: 16),
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
          // Bug 6: hide P/J counter in local mode
          if (!engine.isLocal)
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
      // Bug 1: back button disposes engine and replaces with HomeScreen
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white70),
        onPressed: () => _navigateBack(context, engine),
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
              decoration: _colorSwatchDecoration(teamInfo.color),
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
        resizeToAvoidBottomInset: false,
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
          // Bug 6: hide P/J counter in local mode
          if (!engine.isLocal)
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
      // Bug 1: back button disposes engine and replaces with HomeScreen
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white70),
        onPressed: () => _navigateBack(context, engine),
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
            engine.isLocal
                ? (running ? 'TIMERS RUNNING' : 'TIMERS PAUSED')
                : (running ? 'JAM RUNNING' : 'BETWEEN JAMS'),
            style: AppTextStyles.clockLabel.copyWith(
              color: running ? Colors.greenAccent : Colors.white38,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
          ),
          const Spacer(),
          // Manual timer toggle for offline/local mode
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
                running ? 'PAUSE ALL' : 'RESUME ALL',
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

// Team color picker dialog — preset palette including black and white
class _TeamColorPickerDialog extends StatelessWidget {
  final Color currentColor;

  const _TeamColorPickerDialog({required this.currentColor});

  static final _palette = [
    Colors.black,
    Colors.white,
    Colors.deepOrange.shade400,
    Colors.red.shade400,
    Colors.pink.shade400,
    Colors.purple.shade400,
    Colors.deepPurple.shade400,
    Colors.indigo.shade400,
    Colors.blue.shade400,
    Colors.teal.shade400,
    Colors.green.shade400,
    Colors.lime.shade400,
    Colors.amber.shade400,
    Colors.cyan.shade400,
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1C21),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TEAM COLOR',
              style: AppTextStyles.clockLabel.copyWith(
                color: Colors.white54,
                fontSize: 13,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _palette.map((color) {
                final isSelected = color == currentColor;
                return GestureDetector(
                  onTap: () => Navigator.of(context).pop(color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: _colorSwatchDecoration(color, selected: isSelected),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// BoxDecoration for a color swatch circle.
/// Black gets a persistent white glow so it's visible on the dark background.
/// White gets a subtle grey border. Others glow with their own color when selected.
BoxDecoration _colorSwatchDecoration(Color color, {bool selected = false}) {
  final isBlack = color == Colors.black;
  final isWhite = color == Colors.white;

  final border = Border.all(
    color: selected
        ? Colors.white
        : (isBlack || isWhite)
            ? Colors.white38
            : Colors.transparent,
    width: selected ? 3 : 1.5,
  );

  final List<BoxShadow> shadows = isBlack
      ? [BoxShadow(color: Colors.white.withValues(alpha: selected ? 0.7 : 0.35), blurRadius: 10, spreadRadius: 1)]
      : selected
          ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)]
          : [];

  return BoxDecoration(
    color: color,
    shape: BoxShape.circle,
    border: border,
    boxShadow: shadows,
  );
}

/// Shared back navigation: disposes engine, pushes HomeScreen.
Future<void> _navigateBack(BuildContext context, PenaltyEngine engine) async {
  await engine.dispose();
  if (context.mounted) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }
}

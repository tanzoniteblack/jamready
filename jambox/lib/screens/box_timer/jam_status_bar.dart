import 'package:flutter/material.dart';
import '../../models/penalty_box_state.dart';
import '../../services/penalty_engine.dart';
import '../../styles/text_styles.dart';

/// Shared jam status bar shown across all game screens.
class JamStatusBar extends StatelessWidget {
  final PenaltyBoxState state;
  final PenaltyEngine engine;

  const JamStatusBar({super.key, required this.state, required this.engine});

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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/penalty_box_state.dart';
import '../models/skater_seat.dart';
import '../styles/text_styles.dart';
import 'skater_entry_dialog.dart';

/// Displays the queue of skaters waiting for an open seat (mimics the whiteboard).
class QueuePanel extends StatelessWidget {
  final int teamIndex;
  final bool compact;

  const QueuePanel({super.key, required this.teamIndex, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PenaltyBoxState>();
    final queue = state.queueForTeam(teamIndex);
    final teamColor = state.teamInfo(teamIndex).color;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(Icons.queue, size: 14, color: Colors.white38),
            const SizedBox(width: 6),
            Text(
              'QUEUE',
              style: AppTextStyles.clockLabel.copyWith(
                fontSize: 11,
                color: Colors.white38,
                letterSpacing: 1.5,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _addToQueue(context, state),
              child: Icon(
                Icons.add_circle_outline,
                size: 18,
                color: teamColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        if (queue.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'No skaters queued',
              style: AppTextStyles.infoText.copyWith(
                color: Colors.white24,
                fontSize: 12,
              ),
            ),
          )
        else
          ...queue.map(
            (skater) => _QueueEntry(
              skater: skater,
              teamColor: teamColor,
              compact: compact,
            ),
          ),
      ],
    );
  }

  Future<void> _addToQueue(BuildContext context, PenaltyBoxState state) async {
    final result = await showSkaterEntryDialog(
      context,
      initialPosition: SkaterPosition.blocker,
      teamName: state.teamInfo(teamIndex).name,
    );
    if (result != null) {
      state.addToQueue(
        teamIdx: teamIndex,
        number: result.number,
        position: result.position,
      );
    }
  }
}

class _QueueEntry extends StatelessWidget {
  final SkaterSeat skater;
  final Color teamColor;
  final bool compact;

  const _QueueEntry({
    required this.skater,
    required this.teamColor,
    required this.compact,
  });

  String get _posLabel {
    switch (skater.position) {
      case SkaterPosition.pivot:
        return 'P';
      case SkaterPosition.blocker:
        return 'B';
      case SkaterPosition.jammer:
        return 'J';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<PenaltyBoxState>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: teamColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: teamColor.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '#${skater.skaterNumber}',
                  style: AppTextStyles.clockLabel.copyWith(
                    color: Colors.white,
                    fontSize: compact ? 13 : 15,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: teamColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _posLabel,
                    style: AppTextStyles.clockLabel.copyWith(
                      fontSize: 11,
                      color: Colors.white70,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => state.removeFromQueue(skater),
            child: const Icon(Icons.close, size: 16, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../models/scoreboard_state.dart';
import '../styles/text_styles.dart';
import 'time_edit_dialog.dart';

/// A larger, more prominent period clock display for offline mode.
class ProminentPeriodClock extends StatelessWidget {
  final Clock clock;
  final bool enabled;
  final Function(int) onAdjust;
  final Function(int)? onSetTime;

  const ProminentPeriodClock({
    super.key,
    required this.clock,
    this.enabled = true,
    required this.onAdjust,
    this.onSetTime,
  });

  String _formatTime(int milliseconds) {
    int seconds = (milliseconds / 1000).ceil();
    int minutes = (seconds / 60).floor();
    int remainingSeconds = (seconds % 60);
    return "${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
  }

  Future<void> _handleLongPress(BuildContext context) async {
    // Only allow long press time editing when onSetTime is provided
    if (!enabled || onSetTime == null) return;

    // Haptic feedback for long press
    Vibration.vibrate(duration: 50);

    if (!context.mounted) return;

    final newTimeMs = await TimeEditDialog.show(
      context,
      title: 'Set ${clock.displayName.isNotEmpty ? clock.displayName : clock.name} Time',
      currentTimeMs: clock.time,
      getCurrentTimeMs: () => clock.time,
    );

    if (newTimeMs != null) {
      onSetTime!(newTimeMs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = clock.displayName.isNotEmpty
        ? "${clock.displayName} ${clock.number}"
        : "${clock.name} ${clock.number}";

    final contentColor = enabled ? Colors.white : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.clockLabel.copyWith(
              fontSize: 14,
              color: contentColor.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            // Only enable long press for time editing when onSetTime is provided
            onLongPress: onSetTime != null ? () => _handleLongPress(context) : null,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildAdjustButton("-1", enabled ? () => onAdjust(-1000) : null),
                Text(
                  _formatTime(clock.time),
                  style: AppTextStyles.clockTime.copyWith(
                    fontSize: 48,
                    color: contentColor,
                  ),
                ),
                _buildAdjustButton("+1", enabled ? () => onAdjust(1000) : null),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: 36,
      height: 36,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(
            color: onPressed != null ? Colors.white24 : Colors.white10,
          ),
          shape: const CircleBorder(),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onPressed != null ? Colors.white60 : Colors.white24,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../models/scoreboard_state.dart';
import '../styles/text_styles.dart';

class ClockDisplay extends StatelessWidget {
  final Clock clock;
  final Color? textColor;
  final bool enabled;
  final Function(String) onAdjust;

  const ClockDisplay({
    super.key,
    required this.clock,
    this.textColor,
    this.enabled = true,
    required this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    String label = clock.displayName.toUpperCase();
    if (clock.name == 'Jam' && clock.number > 0) {
      label += " ${clock.number}";
    }

    return Column(
      children: [
        Text(label, style: AppTextStyles.clockLabel),
        const SizedBox(height: 8),
        Text(
          _formatTime(clock.time),
          style: AppTextStyles.clockTime.copyWith(
            color: !enabled
                ? Colors
                      .white12 // Very dim if disconnected
                : textColor ??
                      (clock.running || clock.time > 0
                          ? Colors.white
                          : Colors.white38),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildAdjustButton("-1", enabled ? () => onAdjust("-1000") : null),
            const SizedBox(width: 24),
            _buildAdjustButton("+1", enabled ? () => onAdjust("+1000") : null),
          ],
        ),
      ],
    );
  }

  Widget _buildAdjustButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: 48,
      height: 48,
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
            color: onPressed != null ? Colors.white : Colors.white24,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  String _formatTime(int milliseconds) {
    // Handle negative times if necessary, though usually clocks are positive
    int seconds = (milliseconds / 1000).ceil();
    int minutes = (seconds / 60).floor();
    int remainingSeconds = (seconds % 60);

    // If negative, we might want to show -MM:SS
    if (milliseconds < 0) {
      seconds = (milliseconds.abs() / 1000)
          .floor(); // Use floor for negative to round towards zero
      minutes = (seconds / 60).floor();
      remainingSeconds = (seconds % 60);
      return "-${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
    }

    return "${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
  }
}

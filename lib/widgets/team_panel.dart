import 'package:flutter/material.dart';
import '../models/scoreboard_state.dart';
import '../styles/text_styles.dart';

class TeamPanel extends StatelessWidget {
  final Team team;
  final bool isLeft;
  final bool enabled;

  const TeamPanel({
    super.key,
    required this.team,
    this.isLeft = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: enabled ? 0.05 : 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: enabled ? 0.1 : 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: isLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Text(
            team.displayName,
            style: AppTextStyles.teamName.copyWith(
              color: enabled ? Colors.white : Colors.white38,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          _buildStatRow("TIMEOUTS", team.timeouts.toString()),
          const SizedBox(height: 4),
          _buildStatRow("REVIEWS", team.officialReviews.toString()),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    final Color valueColor = enabled ? Colors.white : Colors.white38;
    final Color labelColor = enabled ? Colors.white70 : Colors.white24;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: isLeft
          ? [
              Text(
                value,
                style: AppTextStyles.clockLabel.copyWith(
                  color: valueColor,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.clockLabel.copyWith(
                  fontSize: 12,
                  color: labelColor,
                ),
              ),
            ]
          : [
              Text(
                label,
                style: AppTextStyles.clockLabel.copyWith(
                  fontSize: 12,
                  color: labelColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: AppTextStyles.clockLabel.copyWith(
                  color: valueColor,
                  fontSize: 18,
                ),
              ),
            ],
    );
  }
}

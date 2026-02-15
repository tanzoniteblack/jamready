import 'package:flutter/material.dart';
import '../models/scoreboard_state.dart';
import '../styles/text_styles.dart';

class TeamPanel extends StatelessWidget {
  final Team team;
  final bool isLeft;

  const TeamPanel({super.key, required this.team, this.isLeft = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: isLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Text(
            team.displayName,
            style: AppTextStyles.teamName,
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: isLeft
          ? [
              Text(
                value,
                style: AppTextStyles.clockLabel.copyWith(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: AppTextStyles.clockLabel.copyWith(fontSize: 12),
              ),
            ]
          : [
              Text(
                label,
                style: AppTextStyles.clockLabel.copyWith(fontSize: 12),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: AppTextStyles.clockLabel.copyWith(
                  color: Colors.white,
                  fontSize: 18,
                ),
              ),
            ],
    );
  }
}

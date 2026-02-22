import 'package:flutter/material.dart';
import '../models/scoreboard_state.dart';
import '../styles/text_styles.dart';

class TeamPanel extends StatelessWidget {
  final Team team;
  final bool isLeft;
  final bool enabled;
  final ValueChanged<bool>? onRetainedToggle;

  const TeamPanel({
    super.key,
    required this.team,
    this.isLeft = true,
    this.enabled = true,
    this.onRetainedToggle,
  });

  Color? _parseColor(String hex) {
    if (hex.isEmpty) return null;
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length == 8) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return Color(value);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _parseColor(team.colorBg);
    final fgColor = _parseColor(team.colorFg);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            bgColor?.withValues(alpha: 0.3) ??
            Colors.white.withValues(alpha: enabled ? 0.05 : 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              bgColor?.withValues(alpha: 0.5) ??
              Colors.white.withValues(alpha: enabled ? 0.1 : 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: isLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Text(
            team.displayName,
            style: AppTextStyles.clockLabel.copyWith(
              fontSize: 22,
              color: fgColor ?? (enabled ? Colors.white70 : Colors.white38),
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          _buildStatRow("TO", team.timeouts.toString()),
          const SizedBox(height: 3),
          _buildStatRow("OR", team.officialReviews.toString()),
          if (onRetainedToggle != null) ...[
            const SizedBox(height: 6),
            _buildRetainedToggle(),
          ],
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
                  fontSize: 16,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.clockLabel.copyWith(
                  fontSize: 14,
                  color: labelColor,
                ),
              ),
            ]
          : [
              Text(
                label,
                style: AppTextStyles.clockLabel.copyWith(
                  fontSize: 14,
                  color: labelColor,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                style: AppTextStyles.clockLabel.copyWith(
                  color: valueColor,
                  fontSize: 16,
                ),
              ),
            ],
    );
  }

  Widget _buildRetainedToggle() {
    final isActive = team.retainedOfficialReview;
    return SizedBox(
      height: 24,
      child: OutlinedButton(
        onPressed: enabled
            ? () => onRetainedToggle?.call(!team.retainedOfficialReview)
            : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          backgroundColor: isActive ? Colors.blue.withValues(alpha: 0.2) : null,
          side: BorderSide(
            color: isActive ? Colors.blue.shade300 : Colors.white24,
            width: isActive ? 1.5 : 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          "RET",
          style: TextStyle(
            color: enabled
                ? (isActive ? Colors.blue.shade300 : Colors.white54)
                : Colors.white24,
            fontSize: 9,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../models/skater_seat.dart';
import '../../styles/text_styles.dart';

/// Role selector — each card starts the game immediately on tap.
class RoleSelector extends StatelessWidget {
  final String team1Name;
  final String team2Name;
  final Color team1Color;
  final Color team2Color;
  final void Function(AppRole) onTap;

  const RoleSelector({
    super.key,
    required this.team1Name,
    required this.team2Name,
    required this.team1Color,
    required this.team2Color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget roleRow(List<({AppRole role, String label, String subtitle, IconData icon, Color color})> options) {
      return Row(
        children: options
            .expand((opt) => [
                  Expanded(
                    child: _RoleOption(
                      role: opt.role,
                      label: opt.label,
                      subtitle: opt.subtitle,
                      icon: opt.icon,
                      color: opt.color,
                      onTap: onTap,
                    ),
                  ),
                  if (opt != options.last) const SizedBox(width: 10),
                ])
            .toList(),
      );
    }

    return Column(
      children: [
        roleRow([
          (role: AppRole.pbm, label: 'PBM', subtitle: 'Both jammers', icon: Icons.swap_horiz, color: Colors.deepOrange.shade400),
          (role: AppRole.solo, label: 'Solo', subtitle: 'All seats', icon: Icons.grid_view, color: Colors.purple.shade400),
        ]),
        const SizedBox(height: 10),
        roleRow([
          (role: AppRole.team1BlockersOnly, label: team1Name, subtitle: '3 blockers', icon: Icons.people_outline, color: team1Color),
          (role: AppRole.team1Full, label: team1Name, subtitle: 'Jammer + blockers', icon: Icons.timer, color: team1Color),
        ]),
        const SizedBox(height: 10),
        roleRow([
          (role: AppRole.team2BlockersOnly, label: team2Name, subtitle: '3 blockers', icon: Icons.people_outline, color: team2Color),
          (role: AppRole.team2Full, label: team2Name, subtitle: 'Jammer + blockers', icon: Icons.timer, color: team2Color),
        ]),
      ],
    );
  }
}

class _RoleOption extends StatelessWidget {
  final AppRole role;
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final void Function(AppRole) onTap;

  const _RoleOption({
    required this.role,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(role),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.clockLabel.copyWith(
                      color: color,
                      fontSize: 20,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: AppTextStyles.infoText.copyWith(
                fontSize: 15,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

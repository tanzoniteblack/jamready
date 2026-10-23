import 'package:flutter/material.dart';

import '../../models/skater_seat.dart';
import '../../styles/text_styles.dart';

/// Chooses the timers a user needs and opens them in a single tap.
///
/// The penalty box timer (PBT) and manager (PBM) views are featured; the
/// remaining views sit below them in a quieter "other views" section.
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
    final teams = [
      (name: team1Name, color: team1Color),
      (name: team2Name, color: team2Color),
    ];
    Widget tile(_ViewChoice choice) =>
        _ChoiceTile(choice: choice, teams: teams, onTap: onTap);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final choice in _ViewChoice.featured) ...[
          tile(choice),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Text(
          'OTHER VIEWS',
          style: AppTextStyles.clockLabel.copyWith(
            color: Colors.white38,
            fontSize: 12,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),
        for (final choice in _ViewChoice.other) ...[
          tile(choice),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

typedef _Team = ({String name, Color color});

final _accent = Colors.deepOrange.shade300;

/// Ordered by how likely each view is to be used, most likely first.
enum _ViewChoice {
  blockersOnly,
  jammersOnly,
  fullTeam,
  allPlayers;

  static Iterable<_ViewChoice> get featured =>
      values.where((choice) => choice.roleTag != null);

  static Iterable<_ViewChoice> get other =>
      values.where((choice) => choice.roleTag == null);
}

extension on _ViewChoice {
  String get label => switch (this) {
    _ViewChoice.blockersOnly => 'Blockers only',
    _ViewChoice.jammersOnly => 'Jammers only',
    _ViewChoice.fullTeam => 'Full team',
    _ViewChoice.allPlayers => 'All players',
  };

  String get subtitle => switch (this) {
    _ViewChoice.blockersOnly => 'Blocker timers for one team',
    _ViewChoice.jammersOnly => 'Both teams’ jammers',
    _ViewChoice.fullTeam => 'Jammer and blockers for one team',
    _ViewChoice.allPlayers => 'Timers for every player',
  };

  IconData get icon => switch (this) {
    _ViewChoice.blockersOnly => Icons.people_outline,
    _ViewChoice.jammersOnly => Icons.timer_outlined,
    _ViewChoice.fullTeam => Icons.group_outlined,
    _ViewChoice.allPlayers => Icons.groups_outlined,
  };

  /// The officiating position this view serves, if it is a featured one.
  String? get roleTag => switch (this) {
    _ViewChoice.blockersOnly => 'PBT',
    _ViewChoice.jammersOnly => 'PBM',
    _ => null,
  };

  /// Roles for team 1 and team 2, or null when the view covers both teams.
  (AppRole, AppRole)? get teamRoles => switch (this) {
    _ViewChoice.blockersOnly => (
      AppRole.team1BlockersOnly,
      AppRole.team2BlockersOnly,
    ),
    _ViewChoice.fullTeam => (AppRole.team1Full, AppRole.team2Full),
    _ => null,
  };

  AppRole get bothTeamsRole => switch (this) {
    _ViewChoice.jammersOnly => AppRole.pbm,
    _ => AppRole.solo,
  };
}

class _ChoiceTile extends StatelessWidget {
  final _ViewChoice choice;
  final List<_Team> teams;
  final void Function(AppRole) onTap;

  const _ChoiceTile({
    required this.choice,
    required this.teams,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final teamRoles = choice.teamRoles;
    final tag = choice.roleTag;
    final featured = tag != null;

    List<Widget> teamButtons(bool compact) => [
      for (final (index, role) in [teamRoles!.$1, teamRoles.$2].indexed) ...[
        if (index > 0) SizedBox(width: compact ? 8 : 10),
        Expanded(
          child: _TeamButton(
            team: teams[index],
            compact: compact,
            onTap: () => onTap(role),
          ),
        ),
      ],
    ];

    final content = featured
        ? Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(choice.icon, color: _accent),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  choice.label,
                                  style: AppTextStyles.buttonText,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _RoleBadge(tag),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(choice.subtitle, style: AppTextStyles.infoText),
                        ],
                      ),
                    ),
                    if (teamRoles == null)
                      Icon(Icons.chevron_right, color: _accent),
                  ],
                ),
                if (teamRoles != null) ...[
                  const SizedBox(height: 14),
                  Row(children: teamButtons(false)),
                ],
              ],
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(choice.icon, color: Colors.white38, size: 20),
                const SizedBox(width: 12),
                Text(
                  choice.label,
                  style: AppTextStyles.infoText.copyWith(color: Colors.white70),
                ),
                const SizedBox(width: 12),
                if (teamRoles != null)
                  Expanded(child: Row(children: teamButtons(true)))
                else ...[
                  const Spacer(),
                  const Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ],
            ),
          );

    return Material(
      color: featured
          ? Colors.deepOrange.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.02),
      shape: RoundedRectangleBorder(
        side: featured
            ? BorderSide(color: _accent, width: 1.5)
            : const BorderSide(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: teamRoles == null
          ? InkWell(onTap: () => onTap(choice.bothTeamsRole), child: content)
          : content,
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String tag;

  const _RoleBadge(this.tag);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag,
        style: AppTextStyles.clockLabel.copyWith(
          color: _accent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TeamButton extends StatelessWidget {
  final _Team team;
  final bool compact;
  final VoidCallback onTap;

  const _TeamButton({
    required this.team,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        minimumSize: Size.fromHeight(compact ? 36 : 48),
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
        side: BorderSide(
          color: team.color.withValues(alpha: compact ? 0.5 : 0.8),
          width: compact ? 1 : 1.5,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 10 : 12,
            height: compact ? 10 : 12,
            decoration: BoxDecoration(
              color: team.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white38),
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Flexible(
            child: Text(
              team.name,
              style: compact
                  ? AppTextStyles.infoText.copyWith(color: Colors.white70)
                  : AppTextStyles.buttonText,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

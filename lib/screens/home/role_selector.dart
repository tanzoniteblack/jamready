import 'package:flutter/material.dart';

import '../../models/skater_seat.dart';
import '../../styles/text_styles.dart';

/// Chooses the timers a user needs before opening the timer screen.
class RoleSelector extends StatefulWidget {
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
  State<RoleSelector> createState() => _RoleSelectorState();
}

class _RoleSelectorState extends State<RoleSelector> {
  _ViewChoice? _choice;

  void _select(_ViewChoice choice) => setState(() => _choice = choice);

  void _openTeam(int teamIndex) {
    final role = switch ((_choice!, teamIndex)) {
      (_ViewChoice.singleTeam, 1) => AppRole.team1Full,
      (_ViewChoice.singleTeam, 2) => AppRole.team2Full,
      (_ViewChoice.blockersOnly, 1) => AppRole.team1BlockersOnly,
      (_ViewChoice.blockersOnly, 2) => AppRole.team2BlockersOnly,
      _ => throw StateError('A team is only available for team views.'),
    };
    widget.onTap(role);
  }

  @override
  Widget build(BuildContext context) {
    final isTeamChoice =
        _choice == _ViewChoice.singleTeam ||
        _choice == _ViewChoice.blockersOnly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final choice in _ViewChoice.values) ...[
          _ChoiceTile(
            choice: choice,
            selected: _choice == choice,
            onTap: () => _select(choice),
          ),
          const SizedBox(height: 10),
        ],
        if (isTeamChoice) ...[
          const SizedBox(height: 10),
          Text(
            'CHOOSE A TEAM',
            style: AppTextStyles.clockLabel.copyWith(
              color: Colors.white70,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          _TeamTile(
            name: widget.team1Name,
            color: widget.team1Color,
            onTap: () => _openTeam(1),
          ),
          const SizedBox(height: 10),
          _TeamTile(
            name: widget.team2Name,
            color: widget.team2Color,
            onTap: () => _openTeam(2),
          ),
        ] else if (_choice != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: () => widget.onTap(
                _choice == _ViewChoice.allPlayers ? AppRole.solo : AppRole.pbm,
              ),
              child: Text('OPEN TIMERS', style: AppTextStyles.buttonText),
            ),
          ),
        ],
      ],
    );
  }
}

enum _ViewChoice { allPlayers, jammersOnly, singleTeam, blockersOnly }

extension on _ViewChoice {
  String get label => switch (this) {
    _ViewChoice.allPlayers => 'All players',
    _ViewChoice.jammersOnly => 'Jammers only',
    _ViewChoice.singleTeam => 'A single team',
    _ViewChoice.blockersOnly => 'A single team — blockers only',
  };

  String get subtitle => switch (this) {
    _ViewChoice.allPlayers => 'Timers for every player',
    _ViewChoice.jammersOnly => 'Both teams’ jammers',
    _ViewChoice.singleTeam => 'Jammer and blockers for one team',
    _ViewChoice.blockersOnly => 'Blocker timers for one team',
  };

  IconData get icon => switch (this) {
    _ViewChoice.allPlayers => Icons.groups_outlined,
    _ViewChoice.jammersOnly => Icons.timer_outlined,
    _ViewChoice.singleTeam => Icons.group_outlined,
    _ViewChoice.blockersOnly => Icons.people_outline,
  };
}

class _ChoiceTile extends StatelessWidget {
  final _ViewChoice choice;
  final bool selected;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = selected ? Colors.deepOrange.shade300 : Colors.white70;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? Colors.deepOrange.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.04),
            border: Border.all(
              color: selected ? accent : Colors.white24,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(choice.icon, color: accent),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(choice.label, style: AppTextStyles.buttonText),
                    const SizedBox(height: 3),
                    Text(choice.subtitle, style: AppTextStyles.infoText),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  final String name;
  final Color color;
  final VoidCallback onTap;

  const _TeamTile({
    required this.name,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: color.withValues(alpha: 0.8)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(name, style: AppTextStyles.buttonText)),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

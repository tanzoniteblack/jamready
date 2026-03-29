import 'package:flutter/material.dart';
import '../../models/penalty_box_state.dart';
import '../../styles/text_styles.dart';

const teamColors = [
  Colors.white,
  Colors.grey,
  Colors.red,
  Colors.deepOrange,
  Colors.amber,
  Colors.green,
  Colors.blue,
  Colors.purple,
];

/// Team settings section for offline mode.
class TeamSettingsSection extends StatelessWidget {
  final PenaltyBoxState state;

  const TeamSettingsSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TeamRow(teamIndex: 1, state: state),
        const SizedBox(height: 16),
        _TeamRow(teamIndex: 2, state: state),
      ],
    );
  }
}

class _TeamRow extends StatefulWidget {
  final int teamIndex;
  final PenaltyBoxState state;

  const _TeamRow({required this.teamIndex, required this.state});

  @override
  State<_TeamRow> createState() => _TeamRowState();
}

class _TeamRowState extends State<_TeamRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.state.teamInfo(widget.teamIndex).name);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final teamInfo = widget.state.teamInfo(widget.teamIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Team ${widget.teamIndex}',
          style: AppTextStyles.clockLabel.copyWith(
            color: Colors.white54,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: widget.teamIndex == 1 ? 'Salt' : 'Pepper',
            hintStyle: const TextStyle(color: Colors.white24),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.white24),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: teamInfo.color, width: 2),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: (value) {
            widget.state.updateTeam(widget.teamIndex, name: value);
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          children: teamColors.map((color) {
            final isSelected = teamInfo.color == color;
            return GestureDetector(
              onTap: () => widget.state.setTeamColor(widget.teamIndex, color),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: isSelected ? 3 : 0,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

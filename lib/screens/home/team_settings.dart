import 'package:flutter/material.dart';
import '../../models/penalty_box_state.dart';
import '../../styles/text_styles.dart';
import '../box_timer/team_color_picker.dart';

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
    _controller = TextEditingController(
      text: widget.state.teamInfo(widget.teamIndex).name,
    );
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
        Row(
          children: [
            Expanded(
              child: Text(
                'Team ${widget.teamIndex}',
                style: AppTextStyles.clockLabel.copyWith(
                  color: Colors.white54,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                _ColorButton(
                  label: 'Jersey',
                  color: teamInfo.fgColor,
                  onTap: () => _showColorPicker(
                    context,
                    currentColor: teamInfo.fgColor,
                    onPicked: (color) => widget.state.updateTeam(
                      widget.teamIndex,
                      fgColor: color,
                    ),
                  ),
                ),
                _ColorButton(
                  label: 'Background',
                  color: teamInfo.bgColor,
                  onTap: () => _showColorPicker(
                    context,
                    currentColor: teamInfo.bgColor,
                    onPicked: (color) => widget.state.updateTeam(
                      widget.teamIndex,
                      bgColor: color,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
              borderSide: BorderSide(color: teamInfo.fgColor, width: 2),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          onChanged: (value) {
            widget.state.updateTeam(widget.teamIndex, name: value);
          },
        ),
      ],
    );
  }

  void _showColorPicker(
    BuildContext context, {
    required Color currentColor,
    required ValueChanged<Color> onPicked,
  }) {
    showDialog<Color>(
      context: context,
      builder: (_) => TeamColorPickerDialog(currentColor: currentColor),
    ).then((color) {
      if (color != null) onPicked(color);
    });
  }
}

class _ColorButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ColorButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}

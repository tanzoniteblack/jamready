import 'package:flutter/material.dart';
import '../../styles/text_styles.dart';
import 'shared_helpers.dart';

/// Team color picker dialog — preset palette including black and white.
class TeamColorPickerDialog extends StatelessWidget {
  final Color currentColor;

  const TeamColorPickerDialog({super.key, required this.currentColor});

  static final _palette = [
    Colors.black,
    Colors.white,
    Colors.deepOrange.shade400,
    Colors.red.shade400,
    Colors.pink.shade400,
    Colors.purple.shade400,
    Colors.deepPurple.shade400,
    Colors.indigo.shade400,
    Colors.blue.shade400,
    Colors.teal.shade400,
    Colors.green.shade400,
    Colors.lime.shade400,
    Colors.amber.shade400,
    Colors.cyan.shade400,
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1A1C21),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TEAM COLOR',
              style: AppTextStyles.clockLabel.copyWith(
                color: Colors.white54,
                fontSize: 13,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: _palette.map((color) {
                final isSelected = color == currentColor;
                return GestureDetector(
                  onTap: () => Navigator.of(context).pop(color),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: colorSwatchDecoration(color, selected: isSelected),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

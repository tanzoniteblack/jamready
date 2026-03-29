import 'package:flutter/material.dart';
import '../../styles/text_styles.dart';

/// Builds a divider with centered text label.
Widget divider(String text) {
  return Row(
    children: [
      Expanded(child: Divider(color: Colors.white24)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(text, style: AppTextStyles.clockLabel.copyWith(color: Colors.white38, fontSize: 11)),
      ),
      Expanded(child: Divider(color: Colors.white24)),
    ],
  );
}

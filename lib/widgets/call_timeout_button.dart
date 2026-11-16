import 'package:flutter/material.dart';
import '../styles/text_styles.dart';

/// Amber outlined button used to call a timeout from the main control deck.
class CallTimeoutButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final double scaleFactor;

  const CallTimeoutButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.scaleFactor = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final color = Colors.amber.shade700;
    final fillTop = enabled
        ? color.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.05);
    final fillBottom = enabled
        ? color.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.02);

    return Container(
      height: 52 * scaleFactor,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12 * scaleFactor),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.12),
                  blurRadius: 6 * scaleFactor,
                  offset: Offset(0, 1.5 * scaleFactor),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(12 * scaleFactor),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [fillTop, fillBottom],
              ),
              borderRadius: BorderRadius.circular(12 * scaleFactor),
              border: Border.all(
                color: enabled ? color : Colors.white12,
                width: 1.5 * scaleFactor,
              ),
            ),
            child: Container(
              alignment: Alignment.center,
              child: Text(
                label.toUpperCase(),
                style: AppTextStyles.buttonText.copyWith(
                  fontSize: 16 * scaleFactor,
                  color: enabled ? Colors.amber.shade200 : Colors.white38,
                  letterSpacing: 0.45,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

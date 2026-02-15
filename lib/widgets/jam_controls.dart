import 'package:flutter/material.dart';
import '../styles/text_styles.dart';

class JamControls extends StatelessWidget {
  final bool inJam;
  final bool isPrePeriod;
  final bool isIntermission;
  final String startLabel;
  final String stopLabel;
  final String timeoutLabel;
  final Color? alertColor;
  final bool enabled;
  final VoidCallback onStartJam;
  final VoidCallback onStopJam;
  final VoidCallback onTimeout;

  const JamControls({
    super.key,
    required this.inJam,
    this.isPrePeriod = false,
    this.isIntermission = false,
    required this.startLabel,
    required this.stopLabel,
    required this.timeoutLabel,
    this.alertColor,
    this.enabled = true,
    required this.onStartJam,
    required this.onStopJam,
    required this.onTimeout,
  });

  @override
  Widget build(BuildContext context) {
    // Determine button appearance and action
    String label;
    Color color;
    VoidCallback onPressed;

    if (inJam) {
      label = stopLabel;
      color = Colors.red.shade800;
      onPressed = onStopJam;
    } else if (isPrePeriod) {
      label = "Start Lineup";
      color = Colors.orange.shade800;
      onPressed = onStopJam;
    } else {
      label = startLabel;
      color = alertColor ?? Colors.green.shade700;
      onPressed = onStartJam;
    }

    // Disable buttons if not enabled
    if (!enabled) {
      color = Colors.grey.shade800;
      // We keep the label but disable the interaction
    }

    final bool timeoutEnabled = enabled && !isIntermission;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 80,
          child: ElevatedButton(
            onPressed: enabled ? onPressed : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              disabledBackgroundColor: Colors.grey.shade800,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: enabled ? 4 : 0,
            ),
            child: Text(
              label.toUpperCase(),
              style: AppTextStyles.buttonText.copyWith(
                fontSize: 28,
                color: enabled ? Colors.white : Colors.white38,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: timeoutEnabled ? onTimeout : null,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: timeoutEnabled ? Colors.amber : Colors.white12,
                width: 2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              timeoutLabel.toUpperCase(),
              style: AppTextStyles.buttonText.copyWith(
                color: timeoutEnabled ? Colors.amber : Colors.white38,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

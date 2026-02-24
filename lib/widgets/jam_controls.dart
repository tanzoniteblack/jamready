import 'package:flutter/material.dart';
import '../styles/text_styles.dart';
import 'swipe_button.dart';

class JamControls extends StatelessWidget {
  final bool inJam;
  final bool isPrePeriod;
  final bool isIntermission;
  final String startLabel;
  final String stopLabel;
  final String timeoutLabel;
  final Color? alertColor;
  final bool enabled;
  final double scaleFactor;
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
    this.scaleFactor = 1.0,
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
    }

    final bool timeoutEnabled = enabled && !isIntermission;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 80 * scaleFactor,
          child: isPrePeriod
              ? SwipeButton(
                  label: "Slide to Start Lineup",
                  onConfirmed: onStopJam,
                  color: Colors.orange.shade800,
                  enabled: enabled,
                  scaleFactor: scaleFactor,
                )
              : _buildDepthButton(
                  label: label.toUpperCase(),
                  color: color,
                  enabled: enabled,
                  onPressed: onPressed,
                  fontSize: 28 * scaleFactor,
                  height: 80 * scaleFactor,
                ),
        ),
        SizedBox(height: 24 * scaleFactor),
        _buildDepthOutlinedButton(
          label: timeoutLabel.toUpperCase(),
          color: Colors.amber,
          enabled: timeoutEnabled,
          onPressed: onTimeout,
          height: 56 * scaleFactor,
        ),
      ],
    );
  }

  Widget _buildDepthButton({
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onPressed,
    double fontSize = 20,
    double height = 56,
  }) {
    final highlightColor = Color.lerp(color, Colors.white, 0.1)!;
    final shadowColor = Color.lerp(color, Colors.black, 0.15)!;

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16 * scaleFactor),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4 * scaleFactor,
                  offset: Offset(0, 2 * scaleFactor),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(16 * scaleFactor),
          child: Ink(
            decoration: BoxDecoration(
              gradient: enabled
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [highlightColor, color, shadowColor],
                      stops: const [0.0, 0.5, 1.0],
                    )
                  : null,
              color: enabled ? null : Colors.grey.shade800,
              borderRadius: BorderRadius.circular(16 * scaleFactor),
            ),
            child: Container(
              alignment: Alignment.center,
              child: Text(
                label,
                style: AppTextStyles.buttonText.copyWith(
                  fontSize: fontSize,
                  color: enabled ? Colors.white : Colors.white38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDepthOutlinedButton({
    required String label,
    required Color color,
    required bool enabled,
    required VoidCallback onPressed,
    double height = 56,
  }) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12 * scaleFactor),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 4 * scaleFactor,
                  offset: Offset(0, 1 * scaleFactor),
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
              color: (enabled ? color : Colors.white12).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12 * scaleFactor),
              border: Border.all(
                color: enabled ? color : Colors.white12,
                width: 2 * scaleFactor,
              ),
            ),
            child: Container(
              alignment: Alignment.center,
              child: Text(
                label,
                style: AppTextStyles.buttonText.copyWith(
                  fontSize: 18 * scaleFactor,
                  color: enabled ? color : Colors.white38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
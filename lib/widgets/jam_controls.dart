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
    }

    final bool timeoutEnabled = enabled && !isIntermission;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 80,
          child: isPrePeriod
              ? SwipeButton(
                  label: "Slide to Start Lineup",
                  onConfirmed: onStopJam,
                  color: Colors.orange.shade800,
                  enabled: enabled,
                )
              : _buildDepthButton(
                  label: label.toUpperCase(),
                  color: color,
                  enabled: enabled,
                  onPressed: onPressed,
                  fontSize: 28,
                  height: 80,
                ),
        ),
        const SizedBox(height: 24),
        _buildDepthOutlinedButton(
          label: timeoutLabel.toUpperCase(),
          color: Colors.amber,
          enabled: timeoutEnabled,
          onPressed: onTimeout,
          height: 56,
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
    final highlightColor = Color.lerp(color, Colors.white, 0.2)!;
    final shadowColor = Color.lerp(color, Colors.black, 0.3)!;

    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: enabled
            ? [
                // Bottom shadow for depth
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
                // Subtle glow
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              gradient: enabled
                  ? LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [highlightColor, color, shadowColor],
                      stops: const [0.0, 0.4, 1.0],
                    )
                  : null,
              color: enabled ? null : Colors.grey.shade800,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              // Inner highlight overlay
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: enabled ? 0.15 : 0.0),
                    Colors.transparent,
                    Colors.transparent,
                    Colors.black.withValues(alpha: enabled ? 0.1 : 0.0),
                  ],
                  stops: const [0.0, 0.3, 0.7, 1.0],
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: AppTextStyles.buttonText.copyWith(
                  fontSize: fontSize,
                  color: enabled ? Colors.white : Colors.white38,
                  shadows: enabled
                      ? [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
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
        borderRadius: BorderRadius.circular(12),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  (enabled ? color : Colors.white12).withValues(alpha: 0.1),
                  (enabled ? color : Colors.white12).withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: enabled ? color : Colors.white12,
                width: 2,
              ),
            ),
            child: Container(
              alignment: Alignment.center,
              child: Text(
                label,
                style: AppTextStyles.buttonText.copyWith(
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
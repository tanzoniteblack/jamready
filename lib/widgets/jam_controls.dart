import 'package:flutter/material.dart';
import '../styles/text_styles.dart';
import 'swipe_button.dart';

class JamControls extends StatefulWidget {
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

  /// Cooldown duration after pressing start/stop before next press is allowed
  static const Duration cooldownDuration = Duration(milliseconds: 2000);

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
  State<JamControls> createState() => _JamControlsState();
}

class _JamControlsState extends State<JamControls> {
  DateTime? _lastPressTime;

  bool get _inCooldown {
    if (_lastPressTime == null) return false;
    final elapsed = DateTime.now().difference(_lastPressTime!);
    return elapsed < JamControls.cooldownDuration;
  }

  void _handlePress(VoidCallback action) {
    if (_inCooldown) return;
    setState(() {
      _lastPressTime = DateTime.now();
    });
    action();
    // Schedule rebuild after cooldown to re-enable button
    Future.delayed(JamControls.cooldownDuration, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Determine button appearance and action
    String label;
    Color color;
    VoidCallback action;

    if (widget.inJam) {
      label = widget.stopLabel;
      color = Colors.red.shade800;
      action = widget.onStopJam;
    } else if (widget.isPrePeriod) {
      label = "Start Lineup";
      color = Colors.orange.shade800;
      action = widget.onStopJam;
    } else {
      label = widget.startLabel;
      color = widget.alertColor ?? Colors.green.shade700;
      action = widget.onStartJam;
    }

    // Button is disabled if not enabled OR in cooldown
    final bool buttonEnabled = widget.enabled && !_inCooldown;

    // Disable buttons if not enabled
    if (!buttonEnabled) {
      color = Colors.grey.shade800;
    }

    final bool timeoutEnabled = widget.enabled && !widget.isIntermission;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 80 * widget.scaleFactor,
          child: widget.isPrePeriod
              ? SwipeButton(
                  label: "Slide to Start Lineup",
                  onConfirmed: widget.onStopJam,
                  color: Colors.orange.shade800,
                  enabled: widget.enabled,
                  scaleFactor: widget.scaleFactor,
                )
              : _buildDepthButton(
                  label: label.toUpperCase(),
                  color: color,
                  enabled: buttonEnabled,
                  onPressed: () => _handlePress(action),
                  fontSize: 28 * widget.scaleFactor,
                  height: 80 * widget.scaleFactor,
                ),
        ),
        SizedBox(height: 24 * widget.scaleFactor),
        _buildDepthOutlinedButton(
          label: widget.timeoutLabel.toUpperCase(),
          color: Colors.amber,
          enabled: timeoutEnabled,
          onPressed: widget.onTimeout,
          height: 56 * widget.scaleFactor,
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
        borderRadius: BorderRadius.circular(16 * widget.scaleFactor),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 4 * widget.scaleFactor,
                  offset: Offset(0, 2 * widget.scaleFactor),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(16 * widget.scaleFactor),
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
              borderRadius: BorderRadius.circular(16 * widget.scaleFactor),
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
        borderRadius: BorderRadius.circular(12 * widget.scaleFactor),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.15),
                  blurRadius: 4 * widget.scaleFactor,
                  offset: Offset(0, 1 * widget.scaleFactor),
                ),
              ]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(12 * widget.scaleFactor),
          child: Ink(
            decoration: BoxDecoration(
              color: (enabled ? color : Colors.white12).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12 * widget.scaleFactor),
              border: Border.all(
                color: enabled ? color : Colors.white12,
                width: 2 * widget.scaleFactor,
              ),
            ),
            child: Container(
              alignment: Alignment.center,
              child: Text(
                label,
                style: AppTextStyles.buttonText.copyWith(
                  fontSize: 18 * widget.scaleFactor,
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
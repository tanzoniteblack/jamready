import 'package:flutter/material.dart';
import '../models/scoreboard_state.dart';
import '../styles/text_styles.dart';

class ClockDisplay extends StatefulWidget {
  final Clock clock;
  final Color? textColor;
  final bool enabled;
  final Function(String) onAdjust;

  const ClockDisplay({
    super.key,
    required this.clock,
    this.textColor,
    this.enabled = true,
    required this.onAdjust,
  });

  @override
  State<ClockDisplay> createState() => _ClockDisplayState();
}

class _ClockDisplayState extends State<ClockDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Subtle 1-2% scale pulse (0.99 to 1.01)
    _pulseAnimation = Tween<double>(begin: 0.98, end: 1.03).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String label = widget.clock.displayName.toUpperCase();
    if (widget.clock.name == 'Jam' && widget.clock.number > 0) {
      label += " ${widget.clock.number}";
    }

    final color = !widget.enabled
        ? Colors.white12
        : widget.textColor ??
            (widget.clock.running || widget.clock.time > 0
                ? Colors.white
                : Colors.white38);

    // Determine glow color based on clock type
    Color? glowColor;
    if (widget.enabled && widget.clock.running) {
      if (widget.clock.name == 'Intermission') {
        glowColor = Colors.orange;
      } else if (widget.clock.name == 'Timeout') {
        glowColor = Colors.red;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: glowColor?.withValues(alpha: 0.05),
        boxShadow: glowColor != null
            ? [
                BoxShadow(
                  color: glowColor.withValues(alpha: 0.15),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Text(
            label,
            style: AppTextStyles.clockLabel.copyWith(
              fontSize: 22,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: child,
              );
            },
            child: Text(
              _formatTime(widget.clock.time),
              style: AppTextStyles.clockTime.copyWith(color: color),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildAdjustButton(
                  "-1", widget.enabled ? () => widget.onAdjust("-1000") : null),
              const SizedBox(width: 24),
              _buildAdjustButton(
                  "+1", widget.enabled ? () => widget.onAdjust("+1000") : null),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: 48,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(
            color: onPressed != null ? Colors.white24 : Colors.white10,
          ),
          shape: const CircleBorder(),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onPressed != null ? Colors.white : Colors.white24,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  String _formatTime(int milliseconds) {
    int seconds = (milliseconds / 1000).ceil();
    int minutes = (seconds / 60).floor();
    int remainingSeconds = (seconds % 60);

    if (milliseconds < 0) {
      seconds = (milliseconds.abs() / 1000).floor();
      minutes = (seconds / 60).floor();
      remainingSeconds = (seconds % 60);
      return "-${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
    }

    return "${minutes.toString().padLeft(1, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
  }
}
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../models/scoreboard_state.dart';
import '../styles/text_styles.dart';
import 'time_edit_dialog.dart';

class ClockDisplay extends StatefulWidget {
  final Clock clock;
  final Color? textColor;
  final bool enabled;
  final Function(String) onAdjust;
  final Function(int)? onSetTime;

  const ClockDisplay({
    super.key,
    required this.clock,
    this.textColor,
    this.enabled = true,
    required this.onAdjust,
    this.onSetTime,
  });

  @override
  State<ClockDisplay> createState() => _ClockDisplayState();
}

class _ClockDisplayState extends State<ClockDisplay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Spam detection for showing long-press hint
  final List<DateTime> _recentPresses = [];
  bool _showLongPressHint = false;
  static bool _hintShownThisSession = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

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

  void _trackButtonPress() {
    // Only track if long-press is available (local mode)
    if (widget.onSetTime == null || _hintShownThisSession) return;

    final now = DateTime.now();
    _recentPresses.add(now);

    // Remove presses older than 3 seconds
    _recentPresses.removeWhere(
      (time) => now.difference(time).inMilliseconds > 3000,
    );

    // If 5+ presses in 3 seconds, show hint
    if (_recentPresses.length >= 5 && !_showLongPressHint) {
      setState(() => _showLongPressHint = true);
      _hintShownThisSession = true;

      // Auto-hide after 4 seconds
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _showLongPressHint = false);
        }
      });
    }
  }

  void _handleAdjust(String value) {
    _trackButtonPress();
    widget.onAdjust(value);
  }

  Future<void> _handleLongPress() async {
    // Only allow long press time editing in local mode (when onSetTime is provided)
    if (!widget.enabled || widget.onSetTime == null) return;

    // Haptic feedback for long press
    Vibration.vibrate(duration: 50);

    if (!mounted) return;

    final newTimeMs = await TimeEditDialog.show(
      context,
      title: 'Set ${widget.clock.displayName.isNotEmpty ? widget.clock.displayName : widget.clock.name} Time',
      currentTimeMs: widget.clock.time,
      getCurrentTimeMs: () => widget.clock.time,
    );

    if (newTimeMs != null) {
      widget.onSetTime!(newTimeMs);
    }
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

    Color? glowColor;
    if (widget.enabled && widget.clock.running) {
      if (widget.clock.name == 'Intermission') {
        glowColor = Colors.orange;
      } else if (widget.clock.name == 'Timeout') {
        glowColor = Colors.red;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.clockLabel.copyWith(
                  fontSize: 18,
                  color: color,
                  height: 1.0,
                ),
              ),
              GestureDetector(
                // Only enable long press for time editing in local mode
                onLongPress: widget.onSetTime != null ? _handleLongPress : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildAdjustButton(
                        "-1", widget.enabled ? () => _handleAdjust("-1000") : null),
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
                        style: AppTextStyles.clockTime.copyWith(
                          color: color,
                          fontSize: 72,
                        ),
                      ),
                    ),
                    _buildAdjustButton(
                        "+1", widget.enabled ? () => _handleAdjust("+1000") : null),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Long-press hint
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _showLongPressHint
              ? GestureDetector(
                  onTap: () => setState(() => _showLongPressHint = false),
                  child: Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app,
                          size: 16,
                          color: Colors.blue.shade300,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Tip: Long-press the time to jump to any value',
                          style: TextStyle(
                            color: Colors.blue.shade300,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildAdjustButton(String label, VoidCallback? onPressed) {
    return SizedBox(
      width: 36,
      height: 36,
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
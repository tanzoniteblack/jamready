import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import '../models/scoreboard_state.dart';
import '../styles/text_styles.dart';
import 'time_edit_dialog.dart';

/// A larger, more prominent period clock display for offline mode.
class ProminentPeriodClock extends StatefulWidget {
  final Clock clock;
  final bool enabled;
  final Function(int) onAdjust;
  final Function(int)? onSetTime;

  const ProminentPeriodClock({
    super.key,
    required this.clock,
    this.enabled = true,
    required this.onAdjust,
    this.onSetTime,
  });

  @override
  State<ProminentPeriodClock> createState() => _ProminentPeriodClockState();
}

class _ProminentPeriodClockState extends State<ProminentPeriodClock> {
  // Spam detection for showing long-press hint
  final List<DateTime> _recentPresses = [];
  bool _showLongPressHint = false;
  static bool _hintShownThisSession = false;

  String _formatTime(int milliseconds) {
    int seconds = (milliseconds / 1000).ceil();
    int minutes = (seconds / 60).floor();
    int remainingSeconds = (seconds % 60);
    return "${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}";
  }

  void _trackButtonPress() {
    // Only track if long-press is available
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

  void _handleAdjust(int delta) {
    _trackButtonPress();
    widget.onAdjust(delta);
  }

  Future<void> _handleLongPress() async {
    // Only allow long press time editing when onSetTime is provided
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
    final label = widget.clock.displayName.isNotEmpty
        ? "${widget.clock.displayName} ${widget.clock.number}"
        : "${widget.clock.name} ${widget.clock.number}";

    final contentColor = widget.enabled ? Colors.white : Colors.white38;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label.toUpperCase(),
                style: AppTextStyles.clockLabel.copyWith(
                  fontSize: 14,
                  color: contentColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              GestureDetector(
                // Only enable long press for time editing when onSetTime is provided
                onLongPress: widget.onSetTime != null ? _handleLongPress : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildAdjustButton("-1", widget.enabled ? () => _handleAdjust(-1000) : null),
                    Text(
                      _formatTime(widget.clock.time),
                      style: AppTextStyles.clockTime.copyWith(
                        fontSize: 48,
                        color: contentColor,
                      ),
                    ),
                    _buildAdjustButton("+1", widget.enabled ? () => _handleAdjust(1000) : null),
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
            color: onPressed != null ? Colors.white60 : Colors.white24,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

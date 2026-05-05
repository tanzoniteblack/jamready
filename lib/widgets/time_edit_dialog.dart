import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../styles/text_styles.dart';

/// A dialog for editing clock time using wheel pickers.
class TimeEditDialog extends StatefulWidget {
  final String title;
  final int currentTimeMs;
  final int? maxTimeMs;

  /// Callback to get the live current time (for confirmation check)
  final int Function()? getCurrentTimeMs;

  const TimeEditDialog({
    super.key,
    required this.title,
    required this.currentTimeMs,
    this.maxTimeMs,
    this.getCurrentTimeMs,
  });

  /// Shows the dialog and returns the new time in milliseconds, or null if cancelled.
  static Future<int?> show(
    BuildContext context, {
    required String title,
    required int currentTimeMs,
    int? maxTimeMs,
    int Function()? getCurrentTimeMs,
  }) {
    return showDialog<int>(
      context: context,
      builder: (context) => TimeEditDialog(
        title: title,
        currentTimeMs: currentTimeMs,
        maxTimeMs: maxTimeMs,
        getCurrentTimeMs: getCurrentTimeMs,
      ),
    );
  }

  @override
  State<TimeEditDialog> createState() => _TimeEditDialogState();
}

class _TimeEditDialogState extends State<TimeEditDialog> {
  late int _selectedMinutes;
  late int _selectedSeconds;
  late FixedExtentScrollController _minutesController;
  late FixedExtentScrollController _secondsController;
  bool _awaitingConfirmation = false;

  @override
  void initState() {
    super.initState();
    // Parse initial time
    int totalSeconds = (widget.currentTimeMs / 1000).ceil();
    if (totalSeconds < 0) totalSeconds = 0;
    _selectedMinutes = totalSeconds ~/ 60;
    _selectedSeconds = totalSeconds % 60;

    _minutesController = FixedExtentScrollController(
      initialItem: _selectedMinutes,
    );
    _secondsController = FixedExtentScrollController(
      initialItem: _selectedSeconds,
    );
  }

  @override
  void dispose() {
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  int get _selectedTimeMs => (_selectedMinutes * 60 + _selectedSeconds) * 1000;

  int get _currentLiveTimeMs =>
      widget.getCurrentTimeMs?.call() ?? widget.currentTimeMs;

  int get _timeDifferenceMs => _selectedTimeMs - _currentLiveTimeMs;

  bool get _needsConfirmation {
    final diff = _timeDifferenceMs.abs();
    return diff > 15000; // More than 15 seconds difference
  }

  String get _formattedDifference {
    final diffSeconds = (_timeDifferenceMs / 1000).round();
    final absSeconds = diffSeconds.abs();
    final minutes = absSeconds ~/ 60;
    final seconds = absSeconds % 60;

    String timeStr;
    if (minutes > 0) {
      timeStr = '$minutes:${seconds.toString().padLeft(2, '0')}';
    } else {
      timeStr = '${absSeconds}s';
    }

    if (diffSeconds >= 0) {
      return 'adds $timeStr';
    } else {
      return 'removes $timeStr';
    }
  }

  void _handleSubmitTap() {
    if (widget.maxTimeMs != null && _selectedTimeMs > widget.maxTimeMs!) {
      return;
    }

    if (_needsConfirmation && !_awaitingConfirmation) {
      // First tap - enter confirmation state
      setState(() => _awaitingConfirmation = true);
      return;
    }

    // Either no confirmation needed, or this is the second tap
    Navigator.of(context).pop(_selectedTimeMs);
  }

  void _onPickerChanged() {
    // Reset confirmation state when picker values change
    if (_awaitingConfirmation) {
      setState(() => _awaitingConfirmation = false);
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxMinutes = widget.maxTimeMs != null
        ? (widget.maxTimeMs! / 60000).ceil()
        : 99;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      title: Text(
        widget.title,
        textAlign: TextAlign.center,
        style: AppTextStyles.clockLabel.copyWith(
          fontSize: 16,
          color: Colors.white70,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Wheel pickers
          SizedBox(
            height: 180,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Minutes picker
                SizedBox(
                  width: 80,
                  child: CupertinoPicker(
                    scrollController: _minutesController,
                    itemExtent: 50,
                    diameterRatio: 1.2,
                    selectionOverlay: Container(
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: Colors.orange.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                    onSelectedItemChanged: (index) {
                      _selectedMinutes = index;
                      _onPickerChanged();
                    },
                    children: List.generate(
                      maxMinutes + 1,
                      (index) => Center(
                        child: Text(
                          index.toString().padLeft(2, '0'),
                          style: AppTextStyles.clockTime.copyWith(
                            fontSize: 36,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Colon separator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    ':',
                    style: AppTextStyles.clockTime.copyWith(
                      fontSize: 36,
                      color: Colors.white54,
                    ),
                  ),
                ),
                // Seconds picker
                SizedBox(
                  width: 80,
                  child: CupertinoPicker(
                    scrollController: _secondsController,
                    itemExtent: 50,
                    diameterRatio: 1.2,
                    selectionOverlay: Container(
                      decoration: BoxDecoration(
                        border: Border.symmetric(
                          horizontal: BorderSide(
                            color: Colors.orange.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                      ),
                    ),
                    onSelectedItemChanged: (index) {
                      _selectedSeconds = index;
                      _onPickerChanged();
                    },
                    children: List.generate(
                      60,
                      (index) => Center(
                        child: Text(
                          index.toString().padLeft(2, '0'),
                          style: AppTextStyles.clockTime.copyWith(
                            fontSize: 36,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Difference indicator
          if (_needsConfirmation)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _awaitingConfirmation
                      ? Colors.red.withValues(alpha: 0.15)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _awaitingConfirmation
                        ? Colors.red.withValues(alpha: 0.4)
                        : Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _awaitingConfirmation
                          ? Icons.warning_rounded
                          : Icons.access_time,
                      size: 16,
                      color: _awaitingConfirmation ? Colors.red : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _awaitingConfirmation
                          ? 'Tap again to confirm'
                          : 'This $_formattedDifference',
                      style: TextStyle(
                        color: _awaitingConfirmation
                            ? Colors.red
                            : Colors.orange,
                        fontSize: 12,
                        fontWeight: _awaitingConfirmation
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('CANCEL', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: _handleSubmitTap,
          style: TextButton.styleFrom(
            foregroundColor: _awaitingConfirmation
                ? Colors.white
                : (_needsConfirmation ? Colors.orange : Colors.white),
            backgroundColor: _awaitingConfirmation
                ? Colors.red
                : (_needsConfirmation
                      ? Colors.orange.withValues(alpha: 0.15)
                      : null),
          ),
          child: Text(
            _awaitingConfirmation
                ? 'CONFIRM'
                : (_needsConfirmation ? 'CHANGE TIME' : 'SET TIME'),
          ),
        ),
      ],
    );
  }
}

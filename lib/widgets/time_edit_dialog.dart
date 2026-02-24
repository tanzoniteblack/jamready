import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../styles/text_styles.dart';

/// A dialog for editing clock time in MM:SS format.
class TimeEditDialog extends StatefulWidget {
  final String title;
  final int currentTimeMs;
  final int? maxTimeMs;

  const TimeEditDialog({
    super.key,
    required this.title,
    required this.currentTimeMs,
    this.maxTimeMs,
  });

  /// Shows the dialog and returns the new time in milliseconds, or null if cancelled.
  static Future<int?> show(
    BuildContext context, {
    required String title,
    required int currentTimeMs,
    int? maxTimeMs,
  }) {
    return showDialog<int>(
      context: context,
      builder: (context) => TimeEditDialog(
        title: title,
        currentTimeMs: currentTimeMs,
        maxTimeMs: maxTimeMs,
      ),
    );
  }

  @override
  State<TimeEditDialog> createState() => _TimeEditDialogState();
}

class _TimeEditDialogState extends State<TimeEditDialog> {
  late TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatTime(widget.currentTimeMs));
    // Select all text initially for easy replacement
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatTime(int milliseconds) {
    int totalSeconds = (milliseconds / 1000).ceil();
    if (totalSeconds < 0) totalSeconds = 0;
    int minutes = totalSeconds ~/ 60;
    int seconds = totalSeconds % 60;
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  int? _parseTime(String text) {
    // Accept formats: MM:SS, M:SS, :SS, SS
    final trimmed = text.trim();

    // Handle MM:SS or M:SS format
    final colonMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(trimmed);
    if (colonMatch != null) {
      final minutes = int.parse(colonMatch.group(1)!);
      final seconds = int.parse(colonMatch.group(2)!);
      if (seconds >= 60) return null;
      return (minutes * 60 + seconds) * 1000;
    }

    // Handle just seconds (no colon)
    final secondsMatch = RegExp(r'^(\d{1,3})$').firstMatch(trimmed);
    if (secondsMatch != null) {
      final seconds = int.parse(secondsMatch.group(1)!);
      return seconds * 1000;
    }

    return null;
  }

  void _validateAndSubmit() {
    final timeMs = _parseTime(_controller.text);
    if (timeMs == null) {
      setState(() => _errorText = 'Use MM:SS format (e.g., 30:00)');
      return;
    }

    if (widget.maxTimeMs != null && timeMs > widget.maxTimeMs!) {
      final maxFormatted = _formatTime(widget.maxTimeMs!);
      setState(() => _errorText = 'Maximum time is $maxFormatted');
      return;
    }

    Navigator.of(context).pop(timeMs);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        widget.title,
        style: AppTextStyles.clockLabel.copyWith(
          fontSize: 18,
          color: Colors.white,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.datetime,
            textAlign: TextAlign.center,
            style: AppTextStyles.clockTime.copyWith(
              fontSize: 48,
              color: Colors.white,
            ),
            decoration: InputDecoration(
              hintText: '00:00',
              hintStyle: AppTextStyles.clockTime.copyWith(
                fontSize: 48,
                color: Colors.white24,
              ),
              errorText: _errorText,
              errorStyle: const TextStyle(color: Colors.redAccent),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white24),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.orange, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.redAccent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
              LengthLimitingTextInputFormatter(5),
            ],
            onSubmitted: (_) => _validateAndSubmit(),
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Enter time as MM:SS',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'CANCEL',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        TextButton(
          onPressed: _validateAndSubmit,
          style: TextButton.styleFrom(
            foregroundColor: Colors.orange,
          ),
          child: const Text('SET TIME'),
        ),
      ],
    );
  }
}
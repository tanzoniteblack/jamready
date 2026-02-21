import 'package:flutter/material.dart';
import '../styles/text_styles.dart';

class SwipeButton extends StatefulWidget {
  final String label;
  final VoidCallback onConfirmed;
  final Color color;
  final Color iconColor;
  final bool enabled;

  const SwipeButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.color = const Color(0xFFEF6C00), // Orange shade 800 default
    this.iconColor = Colors.white,
    this.enabled = true,
  });

  @override
  State<SwipeButton> createState() => _SwipeButtonState();
}

class _SwipeButtonState extends State<SwipeButton> {
  double _dragValue = 0.0;
  bool _confirmed = false;
  final double _height = 80.0;
  final double _handleWidth = 80.0;
  final double _confirmThreshold = 0.7;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.enabled
        ? widget.color
        : Colors.grey.shade800;
    final contentColor = widget.enabled ? Colors.white : Colors.white38;

    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final maxDrag = maxWidth - _handleWidth;

          return Stack(
            children: [
              // Background Track
              Container(
                decoration: BoxDecoration(
                  color: backgroundColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: backgroundColor, width: 2),
                ),
                padding: EdgeInsets.only(left: _handleWidth, right: 16),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    widget.label.toUpperCase(),
                    style: AppTextStyles.buttonText.copyWith(
                      fontSize: 24,
                      color: contentColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),

              // Progress Indicator (optional, fills behind the handle)
              Container(
                width: _handleWidth + _dragValue,
                decoration: BoxDecoration(
                  color: backgroundColor.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),

              // Slide Handle
              Positioned(
                left: _dragValue,
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (!widget.enabled || _confirmed) return;

                    setState(() {
                      _dragValue += details.delta.dx;
                      if (_dragValue < 0) _dragValue = 0;
                      if (_dragValue > maxDrag) _dragValue = maxDrag;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    if (!widget.enabled || _confirmed) return;

                    if (_dragValue > maxDrag * _confirmThreshold) {
                      // Confirmed
                      setState(() {
                        _dragValue = maxDrag;
                        _confirmed = true;
                      });
                      widget.onConfirmed();
                      // Reset after delay if needed, but usually parent rebuilds
                    } else {
                      // Snap back
                      setState(() {
                        _dragValue = 0;
                      });
                    }
                  },
                  child: Container(
                    width: _handleWidth,
                    height: _height,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(
                        14,
                      ), // Slightly smaller radius to fit inside border
                      boxShadow: [
                        if (widget.enabled)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(2, 0),
                          ),
                      ],
                    ),
                    child: Icon(
                      Icons.double_arrow_rounded,
                      color: widget.iconColor,
                      size: 32,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

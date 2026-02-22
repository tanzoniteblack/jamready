import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _SwipeButtonState extends State<SwipeButton>
    with SingleTickerProviderStateMixin {
  double _dragValue = 0.0;
  bool _confirmed = false;
  bool _isTouching = false;
  final double _height = 80.0;
  final double _handleWidth = 80.0;
  final double _confirmThreshold = 0.7;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        widget.enabled ? widget.color : Colors.grey.shade800;
    final contentColor = widget.enabled ? Colors.white : Colors.white38;

    return SizedBox(
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final maxDrag = maxWidth - _handleWidth;
          final progress = maxDrag > 0 ? _dragValue / maxDrag : 0.0;

          return Stack(
            children: [
              // Background Track with inner shadow effect
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      backgroundColor.withValues(alpha: 0.15),
                      backgroundColor.withValues(alpha: 0.25),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: backgroundColor, width: 2),
                  boxShadow: [
                    // Inner shadow effect (simulated with inset-like shadows)
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    // Inner shadow simulation
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.transparent,
                        Colors.white.withValues(alpha: 0.05),
                      ],
                      stops: const [0.0, 0.3, 1.0],
                    ),
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
              ),

              // Track glow on touch
              if (_isTouching && widget.enabled)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: backgroundColor.withValues(alpha: 0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),

              // Progress Indicator with gradient
              AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: _handleWidth + _dragValue,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      backgroundColor.withValues(alpha: 0.5),
                      backgroundColor.withValues(alpha: 0.3 + (progress * 0.2)),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),

              // Slide Handle
              Positioned(
                left: _dragValue,
                child: GestureDetector(
                  onHorizontalDragStart: (details) {
                    if (!widget.enabled || _confirmed) return;
                    setState(() => _isTouching = true);
                    // Very faint haptic on touch
                    HapticFeedback.selectionClick();
                  },
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

                    setState(() => _isTouching = false);

                    if (_dragValue > maxDrag * _confirmThreshold) {
                      // Confirmed - heavier haptic
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _dragValue = maxDrag;
                        _confirmed = true;
                      });
                      widget.onConfirmed();
                    } else {
                      // Snap back
                      setState(() {
                        _dragValue = 0;
                      });
                    }
                  },
                  onHorizontalDragCancel: () {
                    setState(() {
                      _isTouching = false;
                      _dragValue = 0;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    width: _handleWidth,
                    height: _height,
                    decoration: BoxDecoration(
                      // Gradient background for handle
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(
                              backgroundColor, Colors.white, 0.15)!, // Highlight
                          backgroundColor,
                          Color.lerp(
                              backgroundColor, Colors.black, 0.1)!, // Shadow
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        // Outer glow when touching
                        if (_isTouching && widget.enabled)
                          BoxShadow(
                            color: backgroundColor.withValues(alpha: 0.6),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        // Standard shadow
                        if (widget.enabled)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(2, 2),
                          ),
                      ],
                    ),
                    child: Container(
                      // Inner highlight overlay
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.2),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.1),
                          ],
                          stops: const [0.0, 0.3, 0.7, 1.0],
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.double_arrow_rounded,
                          color: widget.iconColor,
                          size: 32,
                        ),
                      ),
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
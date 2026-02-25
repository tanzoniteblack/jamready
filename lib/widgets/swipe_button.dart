import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../styles/text_styles.dart';

class SwipeButton extends StatefulWidget {
  final String label;
  final VoidCallback onConfirmed;
  final Color color;
  final Color iconColor;
  final bool enabled;
  final bool compact;
  final double scaleFactor;

  const SwipeButton({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.color = const Color(0xFFEF6C00), // Orange shade 800 default
    this.iconColor = Colors.white,
    this.enabled = true,
    this.compact = false,
    this.scaleFactor = 1.0,
  });

  @override
  State<SwipeButton> createState() => _SwipeButtonState();
}

class _SwipeButtonState extends State<SwipeButton>
    with SingleTickerProviderStateMixin {
  double _dragValue = 0.0;
  bool _confirmed = false;
  bool _isTouching = false;
  Timer? _resetTimer;
  final double _confirmThreshold = 0.7;

  double get _height => (widget.compact ? 48.0 : 80.0) * widget.scaleFactor;
  double get _handleWidth => (widget.compact ? 48.0 : 80.0) * widget.scaleFactor;
  double get _fontSize => (widget.compact ? 14.0 : 24.0) * widget.scaleFactor;
  double get _iconSize => (widget.compact ? 20.0 : 32.0) * widget.scaleFactor;
  double get _borderRadius => (widget.compact ? 10.0 : 16.0) * widget.scaleFactor;
  double get _borderWidth => (widget.compact ? 1.0 : 2.0) * widget.scaleFactor;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _resetState() {
    setState(() {
      _dragValue = 0.0;
      _confirmed = false;
      _isTouching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.compact
        ? (widget.enabled ? widget.color : Colors.grey.shade800)
        : (widget.enabled ? widget.color : Colors.grey.shade800);
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
                      backgroundColor.withValues(alpha: widget.compact ? 0.2 : 0.15),
                      backgroundColor.withValues(alpha: widget.compact ? 0.32 : 0.25),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(_borderRadius),
                  border: Border.all(color: backgroundColor, width: _borderWidth),
                  boxShadow: widget.compact
                      ? [
                          BoxShadow(
                            color: backgroundColor.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_borderRadius - 2),
                    gradient: widget.compact
                        ? null
                        : LinearGradient(
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
                  padding: EdgeInsets.only(left: _handleWidth, right: 12),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      widget.label.toUpperCase(),
                      style: AppTextStyles.buttonText.copyWith(
                        fontSize: _fontSize,
                        color: contentColor.withValues(alpha: widget.compact ? 0.82 : 0.5),
                        letterSpacing: widget.compact ? 0.4 : 0.0,
                      ),
                    ),
                  ),
                ),
              ),

              // Track glow on touch (reduced for compact mode)
              if (_isTouching && widget.enabled)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_borderRadius),
                    boxShadow: [
                      BoxShadow(
                        color: backgroundColor.withValues(alpha: widget.compact ? 0.15 : 0.3),
                        blurRadius: widget.compact ? 6 : 12,
                        spreadRadius: widget.compact ? 1 : 2,
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
                      backgroundColor.withValues(alpha: widget.compact ? 0.3 : 0.5),
                      backgroundColor.withValues(alpha: (widget.compact ? 0.2 : 0.3) + (progress * 0.2)),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(_borderRadius),
                ),
              ),

              // Slide Handle
              Positioned(
                left: _dragValue,
                child: GestureDetector(
                  onHorizontalDragStart: (details) {
                    if (!widget.enabled || _confirmed) return;
                    setState(() => _isTouching = true);
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
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _dragValue = maxDrag;
                        _confirmed = true;
                      });
                      widget.onConfirmed();

                      _resetTimer?.cancel();
                      _resetTimer = Timer(const Duration(seconds: 3), () {
                        if (mounted) _resetState();
                      });
                    } else {
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
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(backgroundColor, Colors.white, widget.compact ? 0.1 : 0.15)!,
                          backgroundColor,
                          Color.lerp(backgroundColor, Colors.black, widget.compact ? 0.05 : 0.1)!,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(_borderRadius - 2),
                      boxShadow: [
                        if (_isTouching && widget.enabled)
                          BoxShadow(
                            color: backgroundColor.withValues(alpha: widget.compact ? 0.3 : 0.6),
                            blurRadius: widget.compact ? 6 : 12,
                            spreadRadius: widget.compact ? 0 : 1,
                          ),
                        if (widget.enabled)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: widget.compact ? 0.2 : 0.4),
                            blurRadius: widget.compact ? 3 : 6,
                            offset: Offset(widget.compact ? 1 : 2, widget.compact ? 1 : 2),
                          ),
                      ],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(_borderRadius - 2),
                        gradient: widget.compact
                            ? null
                            : LinearGradient(
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
                          color: widget.iconColor.withValues(alpha: widget.compact ? 0.9 : 1.0),
                          size: _iconSize,
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

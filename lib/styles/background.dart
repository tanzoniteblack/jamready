import 'package:flutter/material.dart';

/// A dynamic background that can reflect the current status color.
class DynamicBackground extends StatelessWidget {
  final Widget child;
  final Color? accentColor;

  const DynamicBackground({
    super.key,
    required this.child,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final glowColor = accentColor ?? const Color(0xFF1E2229);
    final hasAccent = accentColor != null;

    return Stack(
      children: [
        // Layer 1: Solid dark base - the foundational background color
        // Slightly darker than typical dark themes for depth
        Positioned.fill(
          child: Container(
            color: const Color(0xFF0E0F12),
          ),
        ),

        // Layer 2: Accent glow - radial gradient that provides subtle color
        // wash behind the clock area, animated when alert color changes
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.25),
                  radius: 0.85, // Covers ~80% of screen from center
                  colors: hasAccent
                      ? [
                          // Center: accent color darkened 70% toward black for subtlety
                          Color.lerp(glowColor, Colors.black, 0.7)!,
                          // Mid-ring: accent color darkened 85% for fade-out
                          Color.lerp(glowColor, Colors.black, 0.85)!,
                          // Edge: fully transparent to blend with base
                          Colors.transparent,
                        ]
                      : [
                          // Neutral mode: subtle gray lift in center
                          const Color(0xFF1E2229),
                          // Neutral mode: darker gray mid-ring
                          const Color(0xFF14161B),
                          // Edge: transparent
                          Colors.transparent,
                        ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Layer 3: Edge vignette - darkens the screen edges to create
        // a subtle spotlight effect that draws focus toward the center
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.95, // Starts fading near edges
                  colors: [
                    // Center: no darkening
                    Colors.transparent,
                    // Edges: semi-transparent black overlay
                    Color(0x88000000),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Layer 4: Foreground content
        Positioned.fill(child: child),

        // Layer 5: Foreground edge vignette — sits above content so it
        // closes the edges on large devices (e.g. Pro Max). Very faint
        // (~7% black) so it doesn't affect readability.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.1,
                  colors: const [
                    Colors.transparent,
                    Color(0x12000000), // ~7% black
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

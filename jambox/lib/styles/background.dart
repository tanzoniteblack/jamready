import 'package:flutter/material.dart';

/// A dynamic background that reflects the current status color.
/// Matches the jamready app's DynamicBackground exactly.
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
        // Layer 1: Solid dark base
        Positioned.fill(
          child: Container(color: const Color(0xFF0E0F12)),
        ),

        // Layer 2: Accent glow
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.0, -0.25),
                  radius: 0.85,
                  colors: hasAccent
                      ? [
                          Color.lerp(glowColor, Colors.black, 0.7)!,
                          Color.lerp(glowColor, Colors.black, 0.85)!,
                          Colors.transparent,
                        ]
                      : [
                          const Color(0xFF1E2229),
                          const Color(0xFF14161B),
                          Colors.transparent,
                        ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ),

        // Layer 3: Edge vignette
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.95,
                  colors: [Colors.transparent, Color(0x88000000)],
                ),
              ),
            ),
          ),
        ),

        // Layer 4: Foreground content
        Positioned.fill(child: child),

        // Layer 5: Foreground edge vignette
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.1,
                  colors: const [Colors.transparent, Color(0x12000000)],
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

import 'package:flutter/material.dart';

class PremiumBackground extends StatelessWidget {
  final Widget child;

  const PremiumBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ===== Layer 1: base =====
        Positioned.fill(
          child: Container(
            color: const Color(0xFF0E0F12), // slightly deeper than scaffold
          ),
        ),

        // ===== Layer 2: focal radial lift =====
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.0, -0.25), // lift toward top center
                  radius: 1.25,
                  colors: [
                    Color(0xFF1E2229), // 👈 this is the key midtone
                    Color(0xFF14161B),
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
        ),

        // ===== Layer 3: edge vignette =====
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.95,
                  colors: [
                    Colors.transparent,
                    Color(0x88000000), // subtle edge darkening
                  ],
                ),
              ),
            ),
          ),
        ),

        // ===== Foreground =====
        Positioned.fill(child: child),
      ],
    );
  }
}

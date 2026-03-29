import 'package:flutter/material.dart';
import '../../models/skater_seat.dart';
import '../../styles/text_styles.dart';
import '../../widgets/seat_card.dart';

/// Standard AppBar used across all box timer screens.
AppBar standardAppBar({
  required BuildContext context,
  required Widget leading,
  required Widget title,
}) {
  return AppBar(
    toolbarHeight: 60,
    titleSpacing: 16,
    backgroundColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    title: title,
    leading: IconButton(
      icon: leading,
      onPressed: () => Navigator.of(context).pop(),
    ),
    flexibleSpace: Align(
      alignment: Alignment.bottomCenter,
      child: Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
    ),
  );
}

/// Builds a vertical stack of blocker seat cards.
Widget buildBlockerStack(List<SkaterSeat> blockers, {bool compact = true}) {
  return Column(
    children: [
      Expanded(child: SeatCard(seat: blockers[0], compact: compact)),
      const SizedBox(height: 8),
      Expanded(child: SeatCard(seat: blockers[1], compact: compact)),
      const SizedBox(height: 8),
      Expanded(child: SeatCard(seat: blockers[2], compact: compact)),
    ],
  );
}

/// Computes the dynamic accent color based on seat states.
Color? computeAccentFromSeats(Iterable<SkaterSeat> seats, [Color? teamColor]) {
  if (seats.any((s) => s.state == SeatState.done)) return Colors.red.shade700;
  if (seats.any((s) => s.state == SeatState.standing)) return Colors.amber.shade600;
  if (teamColor != null && seats.any((s) => s.state == SeatState.running)) return teamColor;
  return null;
}

/// Builds a team header with color swatch and name.
/// [fgColor] is the text color, [bgColor] is the swatch fill, [glowColor] the glow/shadow.
Widget buildTeamHeader(String name, Color fgColor, Color bgColor, Color glowColor) {
  final shadow = Shadow(color: glowColor.withValues(alpha: 0.8), blurRadius: 8);
  return Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: colorSwatchDecoration(bgColor, glowColor: glowColor),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          name,
          style: AppTextStyles.clockLabel.copyWith(
            color: fgColor,
            fontSize: 13,
            letterSpacing: 1.2,
            shadows: [shadow],
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

/// BoxDecoration for a color swatch circle.
/// [glowColor] overrides the auto-computed shadow (used when CRG provides an explicit glow).
/// Black gets a persistent white glow so it's visible on the dark background.
/// White gets a subtle grey border. Others glow with their own color when selected.
BoxDecoration colorSwatchDecoration(Color color, {bool selected = false, Color? glowColor}) {
  final isBlack = color == Colors.black;
  final isWhite = color == Colors.white;

  final border = Border.all(
    color: selected
        ? Colors.white
        : (isBlack || isWhite)
            ? Colors.white38
            : Colors.transparent,
    width: selected ? 3 : 1.5,
  );

  final List<BoxShadow> shadows = glowColor != null
      ? [BoxShadow(color: glowColor.withValues(alpha: selected ? 0.9 : 0.6), blurRadius: 12, spreadRadius: 2)]
      : isBlack
          ? [BoxShadow(color: Colors.white.withValues(alpha: selected ? 0.7 : 0.35), blurRadius: 10, spreadRadius: 1)]
          : selected
              ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 8)]
              : [];

  return BoxDecoration(
    color: color,
    shape: BoxShape.circle,
    border: border,
    boxShadow: shadows,
  );
}

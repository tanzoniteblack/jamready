import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  static final TextStyle teamName = GoogleFonts.outfit(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  static final TextStyle clockTime = GoogleFonts.robotoMono(
    fontSize: 96,
    fontWeight: FontWeight.w700,
    letterSpacing: -2.0,
    color: Colors.white,
  );

  static final TextStyle clockLabel = GoogleFonts.outfit(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.2,
    color: Colors.white70,
  );

  static final TextStyle buttonText = GoogleFonts.outfit(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static final TextStyle infoText = GoogleFonts.outfit(
    fontSize: 14,
    color: Colors.white60,
  );
  static final TextStyle appBarTitle = GoogleFonts.outfit(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    letterSpacing: 2.0,
    color: Colors.white,
  );
}

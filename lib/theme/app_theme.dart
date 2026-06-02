import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const background = Color(0xFFF9EEE9);
  static const roseGold = Color(0xFFC78372);
  static const brown = Color(0xFF3D241E);
  static const taupe = Color(0xFF8B6F67);
  static const softWhite = Color(0xFFFFFBF8);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,

    textTheme: TextTheme(
      headlineLarge: GoogleFonts.playfairDisplay(
        fontSize: 42,
        fontWeight: FontWeight.w500,
        color: brown,
        height: 1.05,
      ),
      headlineMedium: GoogleFonts.cormorantGaramond(
        fontSize: 38,
        fontWeight: FontWeight.w500,
        color: brown,
      ),
      bodyLarge: GoogleFonts.nunito(
        fontSize: 18,
        color: taupe,
        height: 1.45,
      ),
      bodyMedium: GoogleFonts.nunito(
        fontSize: 15,
        color: taupe,
      ),
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      elevation: 0,
      iconTheme: IconThemeData(color: brown),
    ),
  );
}

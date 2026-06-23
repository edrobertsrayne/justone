import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// Major-second modular scale (ratio 1.125, base 14px) — HANDOFF §6.
abstract final class TypeScale {
  static const double overline = 11.1; // uppercase eyebrows
  static const double caption = 12.4;
  static const double label = 12.4;
  static const double body = 14.0; // anchor
  static const double title = 15.8;
  static const double headline = 22.4;
  static const double display = 35.9;
  static const double numeral = 51.1; // target/streak numerals, clock

  /// Newsreader (serif) — display, headings, task titles, numerals.
  static TextStyle serif(
    double size, {
    FontWeight weight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.newsreader(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );

  /// Nunito Sans — UI, body, labels.
  static TextStyle sans(
    double size, {
    FontWeight weight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    Color? color,
  }) =>
      GoogleFonts.nunitoSans(
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: letterSpacing,
        color: color,
      );
}

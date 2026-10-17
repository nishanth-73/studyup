import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

// Inter only, weights 400-800, line-heights ~1.21x from Figma.
class AppTextStyles {
  static TextStyle _i(
    double s,
    FontWeight w, {
    Color c = AppColors.textPrimary,
    double h = 1.21,
  }) => GoogleFonts.inter(fontSize: s, fontWeight: w, color: c, height: h);

  static TextStyle get splashTitle => _i(44, FontWeight.w800, h: 1.21);
  static TextStyle get display40 => _i(40, FontWeight.w800);
  static TextStyle get display36 => _i(36, FontWeight.w800);
  static TextStyle get display34 => _i(34, FontWeight.w800);
  static TextStyle get title30 => _i(30, FontWeight.w800);
  static TextStyle get title28 => _i(28, FontWeight.w800);
  static TextStyle get title26 => _i(26, FontWeight.w700);
  static TextStyle get timer68 => _i(68, FontWeight.w800);
  static TextStyle get stat26 => _i(26, FontWeight.w800);
  static TextStyle get stat24 => _i(24, FontWeight.w800);
  static TextStyle get section18 => _i(18, FontWeight.w700);
  static TextStyle get body16 => _i(16, FontWeight.w400, h: 1.5);
  static TextStyle get body16Bold => _i(16, FontWeight.w700);
  static TextStyle get body15 => _i(15, FontWeight.w600);
  static TextStyle get body14 => _i(14, FontWeight.w400);
  static TextStyle get body14Bold => _i(14, FontWeight.w700);
  static TextStyle get caption13 => _i(13, FontWeight.w600);
  static TextStyle get caption12 =>
      _i(12, FontWeight.w500, c: AppColors.textSecondary);
  static TextStyle get caption12Bold => _i(12, FontWeight.w600);
  static TextStyle get label11 =>
      _i(11, FontWeight.w700, c: AppColors.textSecondary);
  static TextStyle get label10 =>
      _i(10, FontWeight.w500, c: AppColors.textSecondary);
  static TextStyle get nav10 => _i(10, FontWeight.w500);
  static TextStyle get secondary14 =>
      _i(14, FontWeight.w400, c: AppColors.textSecondary);
  static TextStyle get secondary12 =>
      _i(12, FontWeight.w400, c: AppColors.textSecondary);
}

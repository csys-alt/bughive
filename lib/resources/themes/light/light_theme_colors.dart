import 'package:flutter/material.dart';
import '/resources/themes/color_styles.dart';
import 'package:nylo_framework/nylo_framework.dart';

/* Light Theme Colors
|-------------------------------------------------------------------------- */

class LightThemeColors extends ColorStyles {
  /// Colors for general use.
  @override
  GeneralColors get general => const GeneralColors(
    background: Color(0xFFF7F6F3),
    content: Color(0xFF37352F),
    primaryAccent: Color(0xFF2F3437),
    surface: Colors.white,
    surfaceContent: Color(0xFF37352F),
  );

  /// Colors for the app bar.
  @override
  AppBarColors get appBar => const AppBarColors(
    background: Color(0xFFF7F6F3),
    content: Color(0xFF37352F),
  );

  /// Colors for the bottom tab bar.
  @override
  BottomTabBarColors get bottomTabBar => const BottomTabBarColors(
    background: Color(0xFFF7F6F3),
    iconSelected: Color(0xFF2F3437),
    iconUnselected: Color(0xFF787774),
    labelSelected: Color(0xFF37352F),
    labelUnselected: Color(0xFF787774),
  );
}

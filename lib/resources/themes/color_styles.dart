import 'package:nylo_framework/nylo_framework.dart';

/// Interface for your base styles.
/// Add more styles here and then implement in
/// light_theme_colors.dart and dark_theme_colors.dart.

abstract class ColorStyles extends ThemeColor {
  /// Colors for general use.
  @override
  GeneralColors get general;

  /// Colors for the app bar.
  @override
  AppBarColors get appBar;

  /// Colors for the bottom tab bar.
  @override
  BottomTabBarColors get bottomTabBar;
}

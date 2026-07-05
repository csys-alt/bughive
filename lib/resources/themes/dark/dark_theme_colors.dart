import 'package:nylo_framework/nylo_framework.dart';
import '/resources/themes/color_styles.dart';

/* Dark Theme Colors
|-------------------------------------------------------------------------- */

class DarkThemeColors extends ColorStyles {
  /// Colors for general use.
  @override
  GeneralColors get general => const GeneralColors(
    background: Color(0xFF191919),
    content: Color(0xFFEDECE9),
    primaryAccent: Color(0xFFEDECE9),
    surface: Color(0xFF202020),
    surfaceContent: Color(0xFFEDECE9),
  );

  /// Colors for the app bar.
  @override
  AppBarColors get appBar => const AppBarColors(
    background: Color(0xFF191919),
    content: Color(0xFFEDECE9),
  );

  /// Colors for the bottom tab bar.
  @override
  BottomTabBarColors get bottomTabBar => const BottomTabBarColors(
    background: Color(0xFF191919),
    iconSelected: Color(0xFFEDECE9),
    iconUnselected: Color(0xFF9B9A97),
    labelSelected: Color(0xFFEDECE9),
    labelUnselected: Color(0xFF9B9A97),
  );
}

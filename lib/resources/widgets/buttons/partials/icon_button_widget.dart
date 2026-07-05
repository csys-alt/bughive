import 'package:flutter/material.dart';
import '/resources/widgets/buttons/abstract/app_button.dart';

class IconButton extends StatefulAppButton {
  final Widget icon;
  final Color? backgroundColor;
  final Color? contentColor;
  final double iconSpacing;
  final bool iconLeading;

  IconButton({
    super.key,
    required super.text,
    super.onPressed,
    super.submitForm,
    super.onFailure,
    super.showToastError = true,
    super.loadingStyle,
    super.animationStyle,
    super.splashStyle,
    required this.icon,
    this.backgroundColor,
    this.contentColor,
    this.iconSpacing = 10,
    this.iconLeading = true,
    super.width,
    super.height,
  });

  @override
  Widget buildButton(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = backgroundColor ?? theme.colorScheme.primary;
    final fgColor = contentColor ?? theme.colorScheme.onPrimary;
    final radius = BorderRadius.circular(14);

    final iconWidget = IconTheme(
      data: IconThemeData(color: fgColor, size: 20),
      child: icon,
    );

    return Container(
      width: width ?? double.infinity,
      height: height,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: isDark ? 0.3 : 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (iconLeading) ...[
            iconWidget,
            SizedBox(width: iconSpacing),
          ],
          Text(
            text,
            style: TextStyle(
              color: fgColor,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          if (!iconLeading) ...[
            SizedBox(width: iconSpacing),
            iconWidget,
          ],
        ],
      ),
    );
  }
}

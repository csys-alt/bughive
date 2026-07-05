import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';

class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("Dark Mode", textAlign: TextAlign.center).fontWeightBold(),
          Text("BugHive uses dark mode only.", textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

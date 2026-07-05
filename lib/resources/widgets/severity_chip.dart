import '/app/models/engineering_log.dart';
import 'package:flutter/material.dart';

class SeverityChip extends StatelessWidget {
  final Severity severity;

  const SeverityChip({super.key, required this.severity});

  @override
  Widget build(BuildContext context) {
    final colors = _colors(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.$2),
      ),
      child: Text(
        severity.value,
        style: TextStyle(
          color: colors.$3,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }

  (Color, Color, Color) _colors(Severity severity) {
    switch (severity) {
      case Severity.low:
        return (
          const Color(0xFF1B2A3A),
          const Color(0xFF27496D),
          const Color(0xFF9CCBFF),
        );
      case Severity.medium:
        return (
          const Color(0xFF173526),
          const Color(0xFF275E42),
          const Color(0xFF8FE0B2),
        );
      case Severity.high:
        return (
          const Color(0xFF3B2B1D),
          const Color(0xFF70491F),
          const Color(0xFFFFB56B),
        );
      case Severity.critical:
        return (
          const Color(0xFF3A1D1D),
          const Color(0xFF6D2A2A),
          const Color(0xFFFF9A9A),
        );
    }
  }
}

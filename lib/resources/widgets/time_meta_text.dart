import 'dart:async';

import 'package:flutter/material.dart';

class TimeMetaText extends StatefulWidget {
  final DateTime? createdAt;
  final DateTime? syncAt;
  final String neverLabel;

  const TimeMetaText({
    super.key,
    required this.createdAt,
    required this.syncAt,
    this.neverLabel = "Never synced",
  });

  @override
  State<TimeMetaText> createState() => _TimeMetaTextState();
}

class _TimeMetaTextState extends State<TimeMetaText> {
  // ponytail: single timer, rebuilds every 60s to keep relative text fresh
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 60),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      "${_fixedDate(widget.createdAt)} - ${_relative(widget.syncAt)}",
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: const Color(0xFFB8B5B0),
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  String _fixedDate(DateTime? date) {
    if (date == null) return "NO DATE";
    const months = [
      "JAN",
      "FEB",
      "MAR",
      "APR",
      "MAY",
      "JUN",
      "JUL",
      "AUG",
      "SEP",
      "OCT",
      "NOV",
      "DEC",
    ];
    final local = date.toLocal();
    return "${local.day} ${months[local.month - 1]} ${local.year}";
  }

  String _relative(DateTime? date) {
    if (date == null) return widget.neverLabel;

    final now = DateTime.now();
    var difference = now.difference(date.toLocal());
    if (difference.isNegative &&
        difference.abs() > const Duration(minutes: 1)) {
      final corrected = date.toLocal().subtract(now.timeZoneOffset);
      final correctedDifference = now.difference(corrected);
      if (!correctedDifference.isNegative) {
        difference = correctedDifference;
      }
    }

    if (difference.inMinutes < 1) return "Just now";
    if (difference.inHours < 1) {
      return _unit(difference.inMinutes, "minute");
    }
    if (difference.inDays < 1) return _unit(difference.inHours, "hour");
    if (difference.inDays >= 365) {
      return _unit(difference.inDays ~/ 365, "year");
    }
    if (difference.inDays >= 30) {
      return _unit(difference.inDays ~/ 30, "month");
    }
    return _unit(difference.inDays, "day");
  }

  String _unit(int value, String unit) {
    return "$value $unit${value == 1 ? "" : "s"} ago";
  }
}

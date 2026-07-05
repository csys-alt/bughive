import 'package:flutter/material.dart';

const githubDefaultLabels = <String>[
  "bug",
  "documentation",
  "duplicate",
  "enhancement",
  "good first issue",
  "help wanted",
  "invalid",
  "question",
  "wontfix",
];

const _githubLabelColors = <String, Color>{
  "bug": Color(0xFFD73A4A),
  "documentation": Color(0xFF0075CA),
  "duplicate": Color(0xFFCFD3D7),
  "enhancement": Color(0xFFA2EEEF),
  "good first issue": Color(0xFF7057FF),
  "help wanted": Color(0xFF008672),
  "invalid": Color(0xFFE4E669),
  "question": Color(0xFFD876E3),
  "wontfix": Color(0xFFFFFFFF),
};

class GithubLabelPicker extends StatelessWidget {
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;

  const GithubLabelPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final selectedSet = selected.toSet();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: githubDefaultLabels
          .map((label) {
            final active = selectedSet.contains(label);
            return FilterChip(
              label: Text(label),
              selected: active,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: githubLabelColor(label)),
              ),
              onSelected: enabled
                  ? (value) {
                      final next = {...selectedSet};
                      if (value) {
                        next.add(label);
                      } else {
                        next.remove(label);
                      }
                      onChanged(
                        githubDefaultLabels
                            .where(next.contains)
                            .toList(growable: false),
                      );
                    }
                  : null,
              backgroundColor: const Color(0xFF202020),
              selectedColor: githubLabelColor(label),
              checkmarkColor: githubLabelTextColor(label),
              labelStyle: TextStyle(
                color: active
                    ? githubLabelTextColor(label)
                    : githubLabelColor(label),
                fontWeight: FontWeight.w700,
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class GithubLabelWrap extends StatelessWidget {
  final List<String> labels;

  const GithubLabelWrap({super.key, required this.labels});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: labels
          .map((label) => GithubLabelChip(label: label))
          .toList(growable: false),
    );
  }
}

class GithubLabelChip extends StatelessWidget {
  final String label;

  const GithubLabelChip({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = githubLabelColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: githubLabelTextColor(label),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

Color githubLabelColor(String label) {
  return _githubLabelColors[label.toLowerCase()] ?? const Color(0xFF30302E);
}

Color githubLabelTextColor(String label) {
  return githubLabelColor(label).computeLuminance() > 0.55
      ? Colors.black
      : Colors.white;
}

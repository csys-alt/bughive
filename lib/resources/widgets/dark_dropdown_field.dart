import 'package:flutter/material.dart';

class DarkDropdownField<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) text;
  final ValueChanged<T?>? onChanged;

  const DarkDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.text,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: const Color(0xFFEDECE9),
      letterSpacing: 0,
    );
    const selectedMenuStyle = TextStyle(color: Colors.black);
    const menuStyle = TextStyle(color: Color(0xFFEDECE9));

    return DropdownButtonFormField<T>(
      initialValue: value,
      dropdownColor: const Color(0xFF202020),
      focusColor: Colors.white,
      style: selectedStyle,
      iconEnabledColor: const Color(0xFFEDECE9),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      selectedItemBuilder: (context) => values
          .map((item) => Text(text(item), style: selectedStyle))
          .toList(growable: false),
      items: values
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(
                text(item),
                style: item == value ? selectedMenuStyle : menuStyle,
              ),
            ),
          )
          .toList(growable: false),
      onChanged: onChanged,
    );
  }
}

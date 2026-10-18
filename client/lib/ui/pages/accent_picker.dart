import 'package:flutter/material.dart';

import '../colors.dart';
import '../theme.dart';
import 'widgets.dart';

/// Preset swatches plus a hex field for the progress colour (PRD CLI-41).
class AccentPicker extends StatefulWidget {
  const AccentPicker({
    super.key,
    required this.palette,
    required this.value,
    required this.names,
    required this.customLabel,
    required this.badHex,
    required this.onChanged,
  });

  final Palette palette;
  final Color value;
  final Map<AccentPreset, String> names;
  final String customLabel;
  final String badHex;
  final ValueChanged<Color> onChanged;

  @override
  State<AccentPicker> createState() => _AccentPickerState();
}

class _AccentPickerState extends State<AccentPicker> {
  late final _hex = TextEditingController(text: toHex(widget.value));
  bool _bad = false;

  @override
  void didUpdateWidget(AccentPicker old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && parseHex(_hex.text) != widget.value) {
      _hex.text = toHex(widget.value);
      _bad = false;
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _submit(String text) {
    final c = parseHex(text);
    setState(() => _bad = c == null);
    if (c != null && c != widget.value) widget.onChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final current = presetOf(widget.value.toARGB32());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in accentColors.entries)
          _Swatch(
            palette: p,
            color: e.value,
            label: widget.names[e.key]!,
            selected: e.key == current,
            onTap: () => widget.onChanged(e.value),
          ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Text(widget.customLabel, style: textStyle(13, p.fgMuted)),
        const SizedBox(width: 10),
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: widget.value,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: current == null ? p.fg : p.line, width: current == null ? 2 : 1),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 110,
          child: TextField(
            controller: _hex,
            style: digitsStyle(14, p.fg),
            maxLength: 7,
            decoration: inputDecoration(p, '#RRGGBB').copyWith(counterText: ''),
            onChanged: (t) {
              // Apply as soon as the value is complete; flag errors on submit.
              final c = parseHex(t);
              if (c != null) _submit(t);
            },
            onSubmitted: _submit,
            onTapOutside: (_) => _submit(_hex.text),
          ),
        ),
      ]),
      if (_bad) ...[
        const SizedBox(height: 6),
        Text(widget.badHex, style: textStyle(12, Palette.alert)),
      ],
    ]);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.palette, required this.color, required this.label, required this.selected, required this.onTap});

  final Palette palette;
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 30,
            height: 30,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: selected ? palette.fg : Colors.transparent, width: 2),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
            ),
          ),
        ),
      ),
    );
  }
}

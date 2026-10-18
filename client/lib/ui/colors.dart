/// Progress colours the user can choose (DESIGN §5.1). Amber stays the
/// default; every choice is only ever used as a fill, never for text.
library;

import 'dart:ui';

enum AccentPreset { amber, pine, celadon, sky, indigo, wisteria, rouge, moss }

const defaultAccent = Color(0xFFE0A94A);

const accentColors = <AccentPreset, Color>{
  AccentPreset.amber: defaultAccent,
  AccentPreset.pine: Color(0xFF4F8A6E),
  AccentPreset.celadon: Color(0xFF6AA39A),
  AccentPreset.sky: Color(0xFF5B9BD5),
  AccentPreset.indigo: Color(0xFF4A6FA5),
  AccentPreset.wisteria: Color(0xFF8A72B0),
  AccentPreset.rouge: Color(0xFFB2506B),
  AccentPreset.moss: Color(0xFF8A9A4B),
};

/// The preset matching [argb], if any.
AccentPreset? presetOf(int argb) {
  for (final e in accentColors.entries) {
    if (e.value.toARGB32() == argb) return e.key;
  }
  return null;
}

/// Parses "#RRGGBB" or "RRGGBB" (case-insensitive) into an opaque colour.
Color? parseHex(String input) {
  var t = input.trim();
  if (t.startsWith('#')) t = t.substring(1);
  if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(t)) return null;
  return Color(0xFF000000 | int.parse(t, radix: 16));
}

String toHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

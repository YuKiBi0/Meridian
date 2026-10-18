/// Design tokens from DESIGN §5.
library;

import 'package:flutter/material.dart';

import '../core/display.dart';
import 'colors.dart';

@immutable
class Palette {
  const Palette({
    required this.bg,
    required this.fg,
    required this.fgMuted,
    required this.line,
    required this.track,
    required this.surface,
    required this.brightness,
    this.accent = defaultAccent,
  });

  final Color bg;
  final Color fg;
  final Color fgMuted;
  final Color line;
  final Color track;
  final Color surface;
  final Brightness brightness;

  /// Fill colour of a running countdown; amber unless the user picked
  /// another (DESIGN §5.1).
  final Color accent;

  static const alert = Color(0xFFC8452F);

  static const light = Palette(
    bg: Color(0xFFF5F5F2),
    fg: Color(0xFF111418),
    fgMuted: Color(0xFF6B6F74),
    line: Color(0xFFD6D6D1),
    track: Color(0xFFE4E4DF),
    surface: Color(0xFFFBFBF9),
    brightness: Brightness.light,
  );

  static const dark = Palette(
    bg: Color(0xFF111418),
    fg: Color(0xFFF5F5F2),
    fgMuted: Color(0xFF8D9197),
    line: Color(0xFF2E333A),
    track: Color(0xFF22262C),
    surface: Color(0xFF171A1F),
    brightness: Brightness.dark,
  );

  Palette withAccent(Color c) => Palette(
        bg: bg,
        fg: fg,
        fgMuted: fgMuted,
        line: line,
        track: track,
        surface: surface,
        brightness: brightness,
        accent: c,
      );

  /// Digits colour for a tone. Amber is never used for text (DESIGN §5.2).
  Color digits(Tone t) => switch (t) {
        Tone.muted => fgMuted,
        Tone.live => fg,
        Tone.alert => alert,
      };

  /// Progress fill colour for a tone.
  Color fill(Tone t) => switch (t) {
        Tone.muted => fgMuted,
        Tone.live => accent,
        Tone.alert => alert,
      };
}

const fontFamily = 'Inter';
const cjkFallback = ['Microsoft YaHei UI', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans CJK SC'];

/// Text style for countdown digits: tabular figures so nothing shifts as
/// seconds change; lighter as it gets bigger (DESIGN §5.3).
TextStyle digitsStyle(double size, Color color) => TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: cjkFallback,
      fontSize: size,
      height: 1.0,
      fontWeight: size >= 40 ? FontWeight.w300 : FontWeight.w400,
      letterSpacing: size >= 40 ? -0.02 * size : 0,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

TextStyle textStyle(double size, Color color, {FontWeight weight = FontWeight.w400}) => TextStyle(
      fontFamily: fontFamily,
      fontFamilyFallback: cjkFallback,
      fontSize: size,
      height: 1.4,
      fontWeight: weight,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData themeData(Palette p) => ThemeData(
      brightness: p.brightness,
      useMaterial3: true,
      fontFamily: fontFamily,
      fontFamilyFallback: cjkFallback,
      scaffoldBackgroundColor: p.bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: p.track,
      colorScheme: ColorScheme(
        brightness: p.brightness,
        primary: p.fg,
        onPrimary: p.bg,
        secondary: p.fgMuted,
        onSecondary: p.bg,
        error: Palette.alert,
        onError: const Color(0xFFF5F5F2),
        surface: p.bg,
        onSurface: p.fg,
        outline: p.line,
      ),
      textSelectionTheme: TextSelectionThemeData(cursorColor: p.fg, selectionColor: p.track),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: p.fg, borderRadius: BorderRadius.circular(4)),
        textStyle: textStyle(12, p.bg),
        waitDuration: const Duration(milliseconds: 400),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.fg,
        inactiveTrackColor: p.track,
        thumbColor: p.fg,
        overlayShape: SliderComponentShape.noOverlay,
        trackHeight: 2,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.bg : p.fgMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.fg : p.track),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );

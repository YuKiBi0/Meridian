/// Local, per-machine settings (PRD §8.8).
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ui/colors.dart';

enum ViewStyle { bar, ring, digits, ruler }

/// Where a style sits on the screen.
enum Placement {
  top,
  bottom,
  left,
  right,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  topCenter,
  bottomCenter,
  free,
}

/// Placements each style supports (PRD §8.3), default first.
const placementsFor = <ViewStyle, List<Placement>>{
  ViewStyle.bar: [Placement.top, Placement.bottom, Placement.left, Placement.right],
  ViewStyle.ring: [Placement.topRight, Placement.topLeft, Placement.bottomLeft, Placement.bottomRight, Placement.free],
  ViewStyle.digits: [
    Placement.topRight,
    Placement.topLeft,
    Placement.bottomLeft,
    Placement.bottomRight,
    Placement.topCenter,
    Placement.bottomCenter,
    Placement.free,
  ],
  ViewStyle.ruler: [Placement.top, Placement.bottom],
};

enum SizeStep { small, medium, large }

/// Where reminder cards appear (PRD CLI-61, CLI-67): a corner of the work area, or
/// next to the view.
enum ToastPosition { topRight, topLeft, bottomRight, bottomLeft, followView }

enum ThemeChoice { system, light, dark }

enum LangChoice { system, zh, en }

const barThicknesses = [4.0, 8.0, 16.0, 32.0];
const rulerHeights = [24.0, 40.0];
const margins = [0.0, 8.0, 16.0];

double ringDiameter(SizeStep s) => switch (s) {
      SizeStep.small => 96,
      SizeStep.medium => 144,
      SizeStep.large => 200,
    };

double digitsFontSize(SizeStep s) => switch (s) {
      SizeStep.small => 28,
      SizeStep.medium => 44,
      SizeStep.large => 64,
    };

T _enum<T extends Enum>(List<T> values, String? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

class Settings extends ChangeNotifier {
  Settings(this._prefs) {
    _load();
  }

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  String? address;
  ViewStyle style = ViewStyle.ring;
  final Map<ViewStyle, Placement> placement = {
    for (final s in ViewStyle.values) s: placementsFor[s]!.first,
  };

  /// Top-left of free-positioned styles, relative to the display's work area.
  final Map<ViewStyle, ({double x, double y})> freePosition = {};
  double barThickness = 8;
  bool barShowTime = true;
  SizeStep ringSize = SizeStep.medium;
  SizeStep digitsSize = SizeStep.medium;
  bool digitsShowTitle = true;
  double rulerHeight = 40;
  bool showMarks = true;
  String? displayId;
  double margin = 8;
  bool alwaysOnTop = true;
  bool clickThrough = false;
  double opacity = 1;
  ThemeChoice theme = ThemeChoice.system;

  /// Progress fill colour as opaque ARGB (DESIGN §5.1).
  int accentColor = defaultAccent.toARGB32();
  LangChoice lang = LangChoice.system;
  bool launchAtStartup = false;
  ToastPosition toastPosition = ToastPosition.topRight;

  Placement get currentPlacement => placement[style]!;

  void _load() {
    final p = _prefs;
    address = p.getString('address');
    style = _enum(ViewStyle.values, p.getString('style'), style);
    for (final s in ViewStyle.values) {
      final v = _enum(Placement.values, p.getString('placement.${s.name}'), placement[s]!);
      if (placementsFor[s]!.contains(v)) placement[s] = v;
      final x = p.getDouble('free.${s.name}.x'), y = p.getDouble('free.${s.name}.y');
      if (x != null && y != null) freePosition[s] = (x: x, y: y);
    }
    barThickness = p.getDouble('barThickness') ?? barThickness;
    barShowTime = p.getBool('barShowTime') ?? barShowTime;
    ringSize = _enum(SizeStep.values, p.getString('ringSize'), ringSize);
    digitsSize = _enum(SizeStep.values, p.getString('digitsSize'), digitsSize);
    digitsShowTitle = p.getBool('digitsShowTitle') ?? digitsShowTitle;
    rulerHeight = p.getDouble('rulerHeight') ?? rulerHeight;
    showMarks = p.getBool('showMarks') ?? showMarks;
    displayId = p.getString('displayId');
    margin = p.getDouble('margin') ?? margin;
    alwaysOnTop = p.getBool('alwaysOnTop') ?? alwaysOnTop;
    clickThrough = p.getBool('clickThrough') ?? clickThrough;
    opacity = (p.getDouble('opacity') ?? opacity).clamp(0.4, 1.0);
    theme = _enum(ThemeChoice.values, p.getString('theme'), theme);
    accentColor = 0xFF000000 | (p.getInt('accentColor') ?? accentColor);
    lang = _enum(LangChoice.values, p.getString('lang'), lang);
    launchAtStartup = p.getBool('launchAtStartup') ?? launchAtStartup;
    toastPosition = _enum(ToastPosition.values, p.getString('toastPosition'), toastPosition);
  }

  /// Applies [change], persists everything and notifies listeners.
  void update(void Function(Settings s) change) {
    change(this);
    _save();
    notifyListeners();
  }

  void _save() {
    final p = _prefs;
    if (address == null) {
      p.remove('address');
    } else {
      p.setString('address', address!);
    }
    p.setString('style', style.name);
    for (final s in ViewStyle.values) {
      p.setString('placement.${s.name}', placement[s]!.name);
      final f = freePosition[s];
      if (f != null) {
        p.setDouble('free.${s.name}.x', f.x);
        p.setDouble('free.${s.name}.y', f.y);
      }
    }
    p.setDouble('barThickness', barThickness);
    p.setBool('barShowTime', barShowTime);
    p.setString('ringSize', ringSize.name);
    p.setString('digitsSize', digitsSize.name);
    p.setBool('digitsShowTitle', digitsShowTitle);
    p.setDouble('rulerHeight', rulerHeight);
    p.setBool('showMarks', showMarks);
    if (displayId == null) {
      p.remove('displayId');
    } else {
      p.setString('displayId', displayId!);
    }
    p.setDouble('margin', margin);
    p.setBool('alwaysOnTop', alwaysOnTop);
    p.setBool('clickThrough', clickThrough);
    p.setDouble('opacity', opacity);
    p.setString('theme', theme.name);
    p.setInt('accentColor', accentColor);
    p.setString('lang', lang.name);
    p.setBool('launchAtStartup', launchAtStartup);
    p.setString('toastPosition', toastPosition.name);
  }
}

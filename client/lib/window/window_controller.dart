/// Talks to the native "meridian/window" channel in the Windows runner
/// (windows/runner/flutter_window.cpp). Placement there never activates
/// the window, so re-asserting "always on top" does not steal focus from
/// whatever the user is working in.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// One monitor. Rects are in physical pixels; [scale] is its DPI scale.
class Monitor {
  const Monitor({required this.id, required this.primary, required this.scale, required this.work});

  final String id;
  final bool primary;
  final double scale;
  final Rect work;

  /// Work area in this monitor's logical pixels, the space layouts use.
  Rect get logicalWork => Rect.fromLTWH(work.left / scale, work.top / scale, work.width / scale, work.height / scale);

  String get signature => '$id:$primary:$scale:$work';

  static Rect _rect(Map<Object?, Object?> m) => Rect.fromLTWH(
        (m['x'] as num).toDouble(),
        (m['y'] as num).toDouble(),
        (m['w'] as num).toDouble(),
        (m['h'] as num).toDouble(),
      );

  factory Monitor.fromMap(Map<Object?, Object?> m) => Monitor(
        id: m['id'] as String,
        primary: m['primary'] as bool,
        scale: (m['scale'] as num).toDouble(),
        work: _rect(m['work'] as Map<Object?, Object?>),
      );
}

class WindowController {
  static const _ch = MethodChannel('meridian/window');

  Rect? _bounds;
  bool? _topmost;
  bool? _clickThrough;
  double? _opacity;
  bool? _noActivate;
  bool? _skipTaskbar;

  Future<void> init(String title) async {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(420, 320),
      center: true,
      backgroundColor: Color(0x00000000),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await windowManager.setResizable(false);
      await windowManager.setHasShadow(false);
      await windowManager.setTitle(title);
      await windowManager.show();
    });
  }

  Future<List<Monitor>> monitors() async {
    try {
      final list = await _ch.invokeListMethod<Object?>('monitors') ?? const [];
      final ms = [for (final m in list) Monitor.fromMap(m as Map<Object?, Object?>)];
      if (ms.isNotEmpty) return ms;
    } on MissingPluginException {
      // Not running in the Windows runner (tests).
    }
    return const [Monitor(id: 'default', primary: true, scale: 1, work: Rect.fromLTWH(0, 0, 1920, 1040))];
  }

  static Monitor pick(List<Monitor> ms, String? id) =>
      ms.firstWhere((m) => m.id == id, orElse: () => ms.firstWhere((m) => m.primary, orElse: () => ms.first));

  /// Current window bounds in physical pixels.
  Future<Rect?> bounds() async {
    final m = await _ch.invokeMapMethod<Object?, Object?>('bounds');
    return m == null ? null : Monitor._rect(m);
  }

  /// Places the window at [logical] (in [monitor]'s logical pixels).
  Future<void> setBounds(Rect logical, Monitor monitor) async {
    final s = monitor.scale;
    final r = Rect.fromLTWH(
      (logical.left * s).roundToDouble(),
      (logical.top * s).roundToDouble(),
      (logical.width * s).roundToDouble(),
      (logical.height * s).roundToDouble(),
    );
    if (r == _bounds) return;
    _bounds = r;
    await _ch.invokeMethod('setBounds', {'x': r.left.toInt(), 'y': r.top.toInt(), 'w': r.width.toInt(), 'h': r.height.toInt()});
  }

  Future<void> setTopmost(bool on, {bool force = false}) async {
    if (!force && on == _topmost) return;
    _topmost = on;
    await _ch.invokeMethod('setTopmost', {'on': on});
  }

  Future<void> setClickThrough(bool on) async {
    if (on == _clickThrough) return;
    _clickThrough = on;
    await _ch.invokeMethod('setClickThrough', {'on': on});
  }

  Future<void> setOpacity(double v) async {
    if (v == _opacity) return;
    _opacity = v;
    await _ch.invokeMethod('setOpacity', {'value': v});
  }

  /// In view mode clicks must not take focus; panels need it for typing.
  Future<void> setNoActivate(bool on) async {
    if (on == _noActivate) return;
    _noActivate = on;
    await _ch.invokeMethod('setNoActivate', {'on': on});
  }

  Future<void> setSkipTaskbar(bool on) async {
    if (on == _skipTaskbar) return;
    _skipTaskbar = on;
    await windowManager.setSkipTaskbar(on);
  }

  Future<void> setTitle(String title) => windowManager.setTitle(title);

  Future<void> startDragging() => windowManager.startDragging();

  Future<void> focus() => windowManager.focus();

  Future<void> quit() => windowManager.destroy();
}

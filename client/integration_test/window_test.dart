// Runs on the desktop: flutter test integration_test -d windows (or -d macos)
//
// Drives the real app through style and placement switches and the settings
// panel, and checks every time that the window lands where the layout says
// and that Flutter's view follows it.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meridian/core/connection.dart';
import 'package:meridian/core/countdown.dart';
import 'package:meridian/settings.dart';
import 'package:meridian/ui/app.dart';
import 'package:meridian/ui/styles/bar.dart';
import 'package:meridian/ui/tray.dart';
import 'package:meridian/window/geometry.dart';
import 'package:meridian/window/window_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart' show MenuItem, TrayListener;

const _ch = MethodChannel('meridian/window');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('window follows style, placement and panel switches', (t) async {
    // An address nobody listens on: the app shows its views, waiting.
    SharedPreferences.setMockInitialValues({'address': 'http://127.0.0.1:9/meridian?r=0192f3a4-5b6c-7d8e-9fa0-b1c2d3e4f506', 'style': 'ring'});
    final settings = await Settings.load();
    final window = WindowController();
    await window.init('Meridian test');
    await t.pumpWidget(MeridianApp(settings: settings, connection: ServerConnection(Countdown()), window: window));

    final monitor = WindowController.pick(await window.monitors(), null);
    final work = monitor.logicalWork;
    final s = monitor.scale;
    Rect phys(Rect l) => Rect.fromLTWH((l.left * s).roundToDouble(), (l.top * s).roundToDouble(),
        (l.width * s).roundToDouble(), (l.height * s).roundToDouble());

    final problems = <String>[];
    Future<void> check(String step, Rect logicalWindow) async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await t.pump();
      final want = phys(logicalWindow);
      final b = (await _ch.invokeMapMethod<String, Object?>('bounds'))!;
      final got = Rect.fromLTWH((b['x'] as int).toDouble(), (b['y'] as int).toDouble(), (b['w'] as int).toDouble(),
          (b['h'] as int).toDouble());
      // macOS bounds are in points, like its logical pixels.
      final view = t.binding.platformDispatcher.views.first;
      final metrics = Platform.isMacOS ? view.physicalSize / view.devicePixelRatio : view.physicalSize;
      final line = '$step: want $want, window $got, view $metrics';
      // ignore: avoid_print
      print(line);
      // Windows keeps captioned windows at least ~136x39 px (at 100%): a thin
      // bar may come out taller, never narrower or elsewhere.
      bool fits(double g, double w, double min) => g == w || (w < min * s && g >= w);
      final ok = got.topLeft == want.topLeft &&
          fits(got.width, want.width, 140) &&
          fits(got.height, want.height, 40) &&
          metrics == got.size;
      if (!ok) problems.add(line);
    }

    Rect viewWindow(Size size) =>
        layoutFor(work: work, placement: settings.currentPlacement, viewSize: size, margin: settings.margin).window;
    Size ring() => Size.square(ringDiameter(settings.ringSize));
    Size bar() {
      final p = settings.currentPlacement;
      final cross = barCrossSize(p, settings.barThickness, settings.barShowTime);
      return isVerticalPlacement(p)
          ? Size(cross, work.height - 2 * settings.margin)
          : Size(work.width - 2 * settings.margin, cross);
    }

    final state = t.state(find.byType(MeridianApp)) as TrayListener;
    Future<void> menu(String key) async => state.onTrayMenuItemClick(MenuItem(key: key));

    for (final opacity in [1.0, 0.8]) {
      settings.update((x) => x
        ..opacity = opacity
        ..style = ViewStyle.ring
        ..placement[ViewStyle.ring] = Placement.topRight);
      await check('ring top right (opacity $opacity)', viewWindow(ring()));

      for (final p in [Placement.topLeft, Placement.bottomLeft, Placement.bottomRight, Placement.topRight]) {
        await menu('${MenuKeys.placePrefix}${p.name}');
        await check('ring -> ${p.name}', viewWindow(ring()));
      }

      await menu('${MenuKeys.stylePrefix}${ViewStyle.bar.name}');
      await check('ring -> bar (${settings.currentPlacement.name})', viewWindow(bar()));

      for (final p in [Placement.left, Placement.bottom, Placement.right, Placement.top]) {
        await menu('${MenuKeys.placePrefix}${p.name}');
        await check('bar -> ${p.name}', viewWindow(bar()));
      }

      await menu(MenuKeys.settings);
      await check('bar -> settings', Rect.fromCenter(center: work.center, width: 420, height: 600));
      final close = find.text('关闭').evaluate().isNotEmpty ? find.text('关闭') : find.text('Close');
      await t.tap(close.first);
      await check('settings closed -> bar', viewWindow(bar()));

      await menu('${MenuKeys.stylePrefix}${ViewStyle.ruler.name}');
      await check('bar -> ruler', viewWindow(Size(work.width - 2 * settings.margin, settings.rulerHeight)));

      await menu('${MenuKeys.stylePrefix}${ViewStyle.ring.name}');
      await check('ruler -> ring', viewWindow(ring()));
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}

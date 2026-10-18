// Runs on Windows only: flutter test integration_test/app_test.dart -d windows
//
// Drives the real app through style switches and the settings panel and
// checks that the window, the Flutter view window and Flutter's metrics all
// end up at the size the layout asked for.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meridian/core/connection.dart';
import 'package:meridian/core/countdown.dart';
import 'package:meridian/settings.dart';
import 'package:meridian/ui/app.dart';
import 'package:meridian/ui/styles/bar.dart';
import 'package:meridian/ui/tray.dart';
import 'package:meridian/window/window_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart' show MenuItem, TrayListener;

const _ch = MethodChannel('meridian/window');

Future<Size> _size(String method) async {
  final m = (await _ch.invokeMapMethod<String, Object?>(method))!;
  return Size((m['w'] as int).toDouble(), (m['h'] as int).toDouble());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('window follows style switches and panels', (t) async {
    // An address nobody listens on: the app shows its views, waiting.
    SharedPreferences.setMockInitialValues({'address': 'http://127.0.0.1:9/meridian', 'style': 'ring'});
    final settings = await Settings.load();
    final window = WindowController();
    await window.init('Meridian test');
    await t.pumpWidget(MeridianApp(settings: settings, connection: ServerConnection(Countdown()), window: window));

    final monitor = WindowController.pick(await window.monitors(), null);
    final work = monitor.logicalWork;
    Size phys(Size s) => Size((s.width * monitor.scale).roundToDouble(), (s.height * monitor.scale).roundToDouble());

    final problems = <String>[];
    Future<void> check(String step, Size logical) async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await t.pump();
      final want = phys(logical);
      final got = {
        'window': await _size('bounds'),
        'view window': await _size('contentBounds'),
        'metrics': t.binding.platformDispatcher.views.first.physicalSize,
      };
      final line = '$step: want $want, ${got.entries.map((e) => '${e.key} ${e.value}').join(', ')}';
      // ignore: avoid_print
      print(line);
      if (got.values.any((s) => s != want)) problems.add(line);
    }

    final state = t.state(find.byType(MeridianApp));
    final barTop = Size(work.width - 2 * settings.margin, barCrossSize(Placement.top, settings.barThickness, settings.barShowTime));
    final barLeft = Size(barCrossSize(Placement.left, settings.barThickness, settings.barShowTime), work.height - 2 * settings.margin);

    for (final opacity in [1.0, 0.8]) {
      settings.update((s) => s
        ..opacity = opacity
        ..style = ViewStyle.ring);
      await check('ring (opacity $opacity)', Size.square(ringDiameter(settings.ringSize)));

      settings.update((s) => s.style = ViewStyle.bar);
      await check('ring -> bar top', barTop);

      settings.update((s) => s.placement[ViewStyle.bar] = Placement.left);
      await check('bar left', barLeft);
      settings.update((s) => s.placement[ViewStyle.bar] = Placement.top);

      (state as TrayListener).onTrayMenuItemClick(MenuItem(key: MenuKeys.settings));
      await check('bar -> settings', const Size(420, 560));

      final close = find.text('关闭').evaluate().isNotEmpty ? find.text('关闭') : find.text('Close');
      await t.tap(close.first);
      await check('settings closed -> bar top', barTop);

      settings.update((s) => s.style = ViewStyle.ruler);
      await check('bar -> ruler', Size(work.width - 2 * settings.margin, settings.rulerHeight));

      settings.update((s) => s.style = ViewStyle.ring);
      await check('ruler -> ring', Size.square(ringDiameter(settings.ringSize)));
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}

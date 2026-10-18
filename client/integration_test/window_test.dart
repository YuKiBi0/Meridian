// Runs on Windows only: flutter test integration_test -d windows
//
// First the native setBounds alone, then the real app driven through style
// switches and the settings panel. Every step checks that the window, the
// Flutter view window and Flutter's metrics end up at the requested size.
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

Map<String, int> _rect(int x, int y, int w, int h) => {'x': x, 'y': y, 'w': w, 'h': h};

Future<Size> _size(String method) async {
  final m = (await _ch.invokeMapMethod<String, Object?>(method))!;
  return Size((m['w'] as int).toDouble(), (m['h'] as int).toDouble());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Style switches resize the window several times in a row; the Flutter
  // view must follow every time, with or without a region.
  testWidgets('the view follows native setBounds', (t) async {
    // Same frameless setup as the app.
    await WindowController().init('Meridian test');
    await t.pumpWidget(const ColoredBox(color: Color(0xFF111418)));
    final steps = <(Map<String, int>, List<Map<String, int>>?)>[
      (_rect(100, 100, 144, 144), null), // ring
      (_rect(100, 100, 900, 12), null), // bar
      (_rect(100, 100, 420, 560), null), // settings panel
      (_rect(100, 100, 600, 400), [_rect(0, 0, 144, 144), _rect(280, 200, 320, 96)]), // ring + corner card
      (_rect(100, 100, 144, 144), null), // card gone
      (_rect(100, 100, 900, 40), null), // ruler
    ];
    final problems = <String>[];
    for (final (bounds, region) in steps) {
      await _ch.invokeMethod('setBounds', {...bounds, 'region': ?region});
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await t.pump();
      final want = Size(bounds['w']!.toDouble(), bounds['h']!.toDouble());
      final got = [await _size('bounds'), await _size('contentBounds'), t.binding.platformDispatcher.views.first.physicalSize];
      final line = '$bounds region=${region != null}: want $want, window/view/metrics $got';
      // ignore: avoid_print
      print(line);
      if (got.any((s) => s != want)) problems.add(line);
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  // The popup style must keep the transparent background: where Flutter
  // paints nothing, the screen shows what is behind the window.
  testWidgets('transparent where nothing is painted', (t) async {
    await t.pumpWidget(const Align(
      alignment: Alignment.topLeft,
      child: SizedBox.square(dimension: 20, child: ColoredBox(color: Color(0xFFFF0000))),
    ));
    Future<int> pixel(int x, int y) async => (await _ch.invokeMethod<int>('screenPixel', {'x': x, 'y': y}))!;
    Future<void> settle() async {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await t.pump();
    }

    await _ch.invokeMethod('setBounds', _rect(100, 100, 200, 200));
    await settle();
    final red = await pixel(105, 105);
    final through = await pixel(250, 250);
    await _ch.invokeMethod('setBounds', _rect(700, 500, 200, 200));
    await settle();
    final behind = await pixel(250, 250);
    // ignore: avoid_print
    print('red ${red.toRadixString(16)}, through ${through.toRadixString(16)}, behind ${behind.toRadixString(16)}');
    expect(red, 0x0000FF, reason: 'opaque content is drawn (0x00BBGGRR)');
    expect(through, behind, reason: 'transparent area shows what is behind');
  });

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
      await check('bar -> settings', const Size(420, 600)); // _panelSizes[AppMode.settings]

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

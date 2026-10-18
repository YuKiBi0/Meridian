// Runs on Windows only: flutter test integration_test -d windows
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _ch = MethodChannel('meridian/window');

Map<String, int> _rect(int x, int y, int w, int h) => {'x': x, 'y': y, 'w': w, 'h': h};

Future<Size> _call(String method) async {
  final m = (await _ch.invokeMapMethod<String, Object?>(method))!;
  return Size((m['w'] as int).toDouble(), (m['h'] as int).toDouble());
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Style switches resize the window several times in a row; the Flutter
  // view must follow every time, with or without a region.
  testWidgets('the view follows native setBounds', (t) async {
    await t.pumpWidget(const ColoredBox(color: Color(0xFF111418)));
    final steps = <(Map<String, int>, List<Map<String, int>>?)>[
      (_rect(100, 100, 144, 144), null), // ring
      (_rect(100, 100, 900, 12), null), // bar
      (_rect(100, 100, 420, 560), null), // settings panel
      (_rect(100, 100, 600, 400), [_rect(0, 0, 144, 144), _rect(280, 200, 320, 96)]), // ring + corner card
      (_rect(100, 100, 144, 144), null), // card gone
      (_rect(100, 100, 900, 40), null), // ruler
    ];
    for (final (bounds, region) in steps) {
      await _ch.invokeMethod('setBounds', {...bounds, 'region': ?region});
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await t.pump();
      final want = Size(bounds['w']!.toDouble(), bounds['h']!.toDouble());
      expect(await _call('bounds'), want, reason: 'window for $bounds');
      expect(await _call('contentBounds'), want, reason: 'view window for $bounds');
      expect(t.binding.platformDispatcher.views.first.physicalSize, want, reason: 'Flutter metrics for $bounds');
    }
  });
}

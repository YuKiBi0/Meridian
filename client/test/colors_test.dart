import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian/core/display.dart';
import 'package:meridian/settings.dart';
import 'package:meridian/ui/colors.dart';
import 'package:meridian/ui/theme.dart';
import 'package:meridian/ui/tray_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('hex', () {
    test('parses with and without #', () {
      expect(parseHex('#3a7bd5'), const Color(0xFF3A7BD5));
      expect(parseHex(' 3A7BD5 '), const Color(0xFF3A7BD5));
    });

    test('rejects anything but six hex digits', () {
      for (final bad in ['', '#', '#FFF', '#12345', '#1234567', '#GGGGGG', 'red']) {
        expect(parseHex(bad), isNull, reason: bad);
      }
    });

    test('round-trips', () {
      for (final c in accentColors.values) {
        expect(parseHex(toHex(c)), c);
      }
      expect(toHex(const Color(0xFF00000A)), '#00000A');
    });

    test('presets are distinct and amber is the default', () {
      expect(accentColors.values.toSet().length, accentColors.length);
      expect(presetOf(defaultAccent.toARGB32()), AccentPreset.amber);
      expect(presetOf(0xFF123456), isNull);
    });
  });

  test('palette fills a running countdown with its accent, alerts stay vermilion', () {
    final p = Palette.dark.withAccent(const Color(0xFF4A6FA5));
    expect(p.fill(Tone.live), const Color(0xFF4A6FA5));
    expect(p.fill(Tone.alert), Palette.alert);
    expect(p.fg, Palette.dark.fg);
    expect(Palette.light.fill(Tone.live), defaultAccent);
  });

  test('settings persist the accent', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await Settings.load();
    expect(s.accentColor, defaultAccent.toARGB32());
    s.update((x) => x.accentColor = 0xFF4F8A6E);
    expect((await Settings.load()).accentColor, 0xFF4F8A6E);
  });

  group('ico', () {
    test('encodes a valid 32-bit DIB icon', () {
      final rgba = Uint8List(4 * 4 * 4);
      // Top-left pixel: opaque red.
      rgba.setAll(0, [255, 0, 0, 255]);
      final ico = ByteData.sublistView(encodeIco([(size: 4, rgba: rgba)]));
      expect(ico.getUint16(2, Endian.little), 1); // icon
      expect(ico.getUint16(4, Endian.little), 1); // one image
      expect(ico.getUint8(6), 4);
      final length = ico.getUint32(6 + 8, Endian.little);
      final offset = ico.getUint32(6 + 12, Endian.little);
      expect(offset, 22);
      expect(length, 40 + 64 + 4 * 4); // header, pixels, mask rows of 4 bytes
      expect(ico.lengthInBytes, offset + length);
      expect(ico.getInt32(offset + 8, Endian.little), 8); // doubled height
      // Rows are stored bottom-up in BGRA: the top row comes last.
      final topRow = offset + 40 + 3 * 16;
      expect([for (var i = 0; i < 4; i++) ico.getUint8(topRow + i)], [0, 0, 255, 255]);
    });

    test('renders the mark with the chosen dot colour', () async {
      final img = await renderMark(32, const Color(0xFF111418), const Color(0xFF4A6FA5));
      expect(img.rgba.length, 32 * 32 * 4);
      // Centre of the dot: (8, 5.67) on the 16 grid.
      final i = (11 * 32 + 16) * 4;
      expect(img.rgba.sublist(i, i + 4), [0x4A, 0x6F, 0xA5, 255]);
    });

    test('draws the macOS menu bar icon as a 36 px PNG', () async {
      final png = await menuBarIcon(const Color(0xFF111418), const Color(0xFF111418), hole: const Color(0xFFF5F5F2));
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      final header = ByteData.sublistView(png);
      expect([header.getUint32(16), header.getUint32(20)], [36, 36]);
    });
  });
}

/// Tray icons drawn at runtime, for a progress colour other than the
/// bundled amber (DESIGN §4.4). Same geometry as tool/gen_icons.sh.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'colors.dart';

const _sizes = [16, 20, 24, 32, 40, 48];

/// One square image as straight (non-premultiplied) RGBA rows, top first.
typedef IconImage = ({int size, Uint8List rgba});

/// Packs [images] into an .ico file using 32-bit DIB entries, which every
/// Windows version loads.
Uint8List encodeIco(List<IconImage> images) {
  final entries = BytesBuilder();
  final data = BytesBuilder();
  var offset = 6 + 16 * images.length;
  for (final img in images) {
    final n = img.size;
    final maskStride = ((n + 31) ~/ 32) * 4;
    final dib = ByteData(40 + n * n * 4 + maskStride * n);
    dib
      ..setUint32(0, 40, Endian.little)
      ..setInt32(4, n, Endian.little)
      ..setInt32(8, n * 2, Endian.little) // colour rows + mask rows
      ..setUint16(12, 1, Endian.little)
      ..setUint16(14, 32, Endian.little);
    var o = 40;
    for (var y = n - 1; y >= 0; y--) {
      for (var x = 0; x < n; x++) {
        final i = (y * n + x) * 4;
        dib
          ..setUint8(o++, img.rgba[i + 2])
          ..setUint8(o++, img.rgba[i + 1])
          ..setUint8(o++, img.rgba[i])
          ..setUint8(o++, img.rgba[i + 3]);
      }
    }
    // The AND mask stays zero: alpha carries the transparency.
    final bytes = dib.buffer.asUint8List();
    final entry = ByteData(16)
      ..setUint8(0, n >= 256 ? 0 : n)
      ..setUint8(1, n >= 256 ? 0 : n)
      ..setUint16(4, 1, Endian.little)
      ..setUint16(6, 32, Endian.little)
      ..setUint32(8, bytes.length, Endian.little)
      ..setUint32(12, offset, Endian.little);
    entries.add(entry.buffer.asUint8List());
    data.add(bytes);
    offset += bytes.length;
  }
  final header = ByteData(6)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, images.length, Endian.little);
  return (BytesBuilder()
        ..add(header.buffer.asUint8List())
        ..add(entries.takeBytes())
        ..add(data.takeBytes()))
      .takeBytes();
}

/// Draws the tray mark with a filled dot of [dot] on a 16-unit grid.
Future<IconImage> renderMark(int size, Color body, Color dot) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)..scale(size / 16);
  final stroke = Paint()
    ..color = body
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;
  canvas
    ..drawCircle(const Offset(8, 8), 6, stroke)
    ..drawLine(const Offset(8, 1), const Offset(8, 15), stroke)
    ..drawCircle(const Offset(8, 5.67), 2.25, Paint()..color = dot);
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ImageByteFormat.rawStraightRgba);
  image.dispose();
  return (size: size, rgba: bytes!.buffer.asUint8List());
}

/// Writes (once) and returns the path of the "running" icon in [dot] for a
/// taskbar of [brightness].
Future<String> runningIconFile(Color dot, Brightness brightness) async {
  final theme = brightness == Brightness.dark ? 'paper' : 'ink';
  final body = brightness == Brightness.dark ? const Color(0xFFF5F5F2) : const Color(0xFF111418);
  final hex = toHex(dot).substring(1).toLowerCase();
  final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}meridian${Platform.pathSeparator}running_${hex}_$theme.ico');
  if (!file.existsSync()) {
    final images = [for (final s in _sizes) await renderMark(s, body, dot)];
    await file.parent.create(recursive: true);
    await file.writeAsBytes(encodeIco(images), flush: true);
  }
  return file.path;
}

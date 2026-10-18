import 'package:flutter/widgets.dart';

import '../../core/display.dart';
import '../../settings.dart';
import '../theme.dart';
import 'common.dart';

/// Tick units, smallest first; the first that keeps ticks >= 6 px apart wins.
const _unitsMs = [1000, 5000, 10000, 30000, 60000, 300000, 600000, 900000, 1800000, 3600000];

/// A ruler for the whole run with a line for "now" moving from right to
/// left (PRD CLI-23).
class RulerView extends StatelessWidget {
  const RulerView({
    super.key,
    required this.model,
    required this.totalMs,
    required this.placement,
    required this.palette,
    required this.label,
    required this.linkTooltip,
  });

  final DisplayModel model;
  final int totalMs;
  final Placement placement;
  final Palette palette;
  final String? label;
  final String linkTooltip;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned.fill(
        child: ProgressBuilder(
          value: model.progress,
          builder: (context, p) => CustomPaint(
            painter: _RulerPainter(
              progress: p,
              totalMs: model.hasRun ? totalMs : 0,
              top: placement == Placement.top,
              palette: palette,
              line: palette.fill(model.tone),
              text: pillText(model, label),
              textColor: palette.digits(model.tone),
              hasRun: model.hasRun,
            ),
          ),
        ),
      ),
      Positioned(
        right: 8,
        top: placement == Placement.top ? null : 4,
        bottom: placement == Placement.top ? 4 : null,
        child: LinkDot(model: model, palette: palette, tooltip: linkTooltip),
      ),
    ]);
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.progress,
    required this.totalMs,
    required this.top,
    required this.palette,
    required this.line,
    required this.text,
    required this.textColor,
    required this.hasRun,
  });

  final double progress;
  final int totalMs;
  final bool top;
  final Palette palette;
  final Color line;
  final String text;
  final Color textColor;
  final bool hasRun;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = palette.bg.withValues(alpha: 0.94));
    final edge = Paint()..color = palette.line;
    canvas.drawRect(top ? Rect.fromLTWH(0, h - 1, w, 1) : Rect.fromLTWH(0, 0, w, 1), edge);

    final nowX = hasRun ? w * progress : w;
    var unit = 0;
    var count = 0;
    if (totalMs > 0) {
      unit = _unitsMs.firstWhere((u) => w * u / totalMs >= 6, orElse: () => _unitsMs.last);
      count = totalMs ~/ unit;
    } else {
      count = (w / 12).floor();
    }
    final step = totalMs > 0 ? w * unit / totalMs : 12.0;
    final ahead = Paint()
      ..color = palette.fg
      ..strokeWidth = 1;
    final aheadMinor = Paint()
      ..color = palette.fgMuted
      ..strokeWidth = 1;
    final behind = Paint()
      ..color = palette.fgMuted.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (var i = 0; i <= count; i++) {
      final x = (i * step).roundToDouble() + 0.5;
      if (x > w) break;
      final major = i % 5 == 0;
      final len = h * (major ? 0.45 : 0.22);
      final paint = hasRun && x <= nowX ? (major ? ahead : aheadMinor) : behind;
      if (top) {
        canvas.drawLine(Offset(x, 0), Offset(x, len), paint);
      } else {
        canvas.drawLine(Offset(x, h), Offset(x, h - len), paint);
      }
    }

    final style = digitsStyle(h >= 40 ? 13 : 11, textColor);
    final tw = measure(text, style).width;
    if (hasRun) {
      final x = nowX.clamp(1.0, w - 1);
      canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, h), Paint()..color = line);
      final leftSide = x - tw - 8 >= 0;
      final tx = leftSide ? x - 6 : x + 6;
      final bg = Rect.fromLTWH(leftSide ? tx - tw - 3 : tx - 3, h / 2 - 8, tw + 6, 16);
      canvas.drawRect(bg, Paint()..color = palette.bg);
      paintText(canvas, text, style, Offset(tx, h / 2), align: leftSide ? Alignment.centerRight : Alignment.centerLeft);
    } else {
      final bg = Rect.fromCenter(center: Offset(w / 2, h / 2), width: tw + 12, height: 16);
      canvas.drawRect(bg, Paint()..color = palette.bg);
      paintText(canvas, text, style, Offset(w / 2, h / 2));
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.progress != progress ||
      old.totalMs != totalMs ||
      old.text != text ||
      old.line != line ||
      old.palette != palette ||
      old.top != top;
}

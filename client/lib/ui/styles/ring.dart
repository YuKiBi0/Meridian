import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/display.dart';
import '../theme.dart';
import 'common.dart';

/// Ring progress with the digits in the middle (PRD CLI-21).
class RingView extends StatelessWidget {
  const RingView({
    super.key,
    required this.model,
    required this.palette,
    required this.label,
    required this.showMarks,
    required this.linkTooltip,
  });

  final DisplayModel model;
  final Palette palette;
  final String? label;
  final bool showMarks;
  final String linkTooltip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final d = math.min(c.maxWidth, c.maxHeight);
      final sub = label ?? (model.title.isEmpty ? null : model.title);
      return Stack(children: [
        Positioned.fill(
          child: ProgressBuilder(
            value: model.progress,
            builder: (context, p) => CustomPaint(
              painter: _RingPainter(
                progress: p,
                palette: palette,
                fill: palette.fill(model.tone),
                marks: showMarks ? model.marks : const [],
              ),
            ),
          ),
        ),
        Center(
          child: SizedBox(
            width: d * 0.66,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(model.digits, style: digitsStyle(d * 0.2, palette.digits(model.tone))),
              ),
              if (sub != null) ...[
                SizedBox(height: d * 0.04),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: textStyle(math.max(10, d * 0.075), palette.fgMuted),
                ),
              ],
            ]),
          ),
        ),
        Positioned(
          right: d * 0.06,
          top: d * 0.06,
          child: LinkDot(model: model, palette: palette, tooltip: linkTooltip),
        ),
      ]);
    });
  }
}

double ringStroke(double d) => math.max(3, d * 0.045);

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.palette, required this.fill, required this.marks});

  final double progress;
  final Palette palette;
  final Color fill;
  final List<double> marks;

  @override
  void paint(Canvas canvas, Size size) {
    final d = math.min(size.width, size.height);
    final c = size.center(Offset.zero);
    final outer = d / 2 - 0.5;
    canvas.drawCircle(c, outer, Paint()..color = palette.bg.withValues(alpha: 0.94));
    canvas.drawCircle(
      c,
      outer,
      Paint()
        ..color = palette.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final stroke = ringStroke(d);
    final r = outer - d * 0.08 - stroke / 2;
    final track = Paint()
      ..color = palette.track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(c, r, track);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..color = fill
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
    }
    final notch = Paint()
      ..color = palette.bg
      ..strokeWidth = 1.5;
    for (final m in marks) {
      final a = -math.pi / 2 + 2 * math.pi * m;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * (r - stroke / 2), c + dir * (r + stroke / 2), notch);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.fill != fill || old.palette != palette || old.marks != marks;
}

import 'package:flutter/widgets.dart';

import '../../core/display.dart';
import '../../settings.dart';
import '../theme.dart';
import 'common.dart';

const _pillHeight = 18.0;
const _pillGap = 4.0;
const _pillFont = 11.0;
const verticalPillWidth = 60.0;

/// Whether the time label sits inside the bar rather than beside it.
bool barLabelInside(Placement p, double thickness) => !isVerticalPlacement(p) && thickness >= 16;

bool isVerticalPlacement(Placement p) => p == Placement.left || p == Placement.right;

/// Thickness of the window across the bar.
double barCrossSize(Placement p, double thickness, bool showTime) {
  if (!showTime || barLabelInside(p, thickness)) return thickness;
  return thickness + _pillGap + (isVerticalPlacement(p) ? verticalPillWidth : _pillHeight);
}

/// Thin progress bar along a screen edge (PRD CLI-20). The filled part is
/// the time still remaining: it shrinks toward the start (left, or bottom
/// for vertical bars).
class BarView extends StatelessWidget {
  const BarView({
    super.key,
    required this.model,
    required this.placement,
    required this.thickness,
    required this.showTime,
    required this.showMarks,
    required this.palette,
    required this.label,
    required this.linkTooltip,
  });

  final DisplayModel model;
  final Placement placement;
  final double thickness;
  final bool showTime;
  final bool showMarks;
  final Palette palette;
  final String? label;
  final String linkTooltip;

  @override
  Widget build(BuildContext context) {
    final vertical = isVerticalPlacement(placement);
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      final barRect = switch (placement) {
        Placement.bottom => Rect.fromLTWH(0, size.height - thickness, size.width, thickness),
        Placement.right => Rect.fromLTWH(size.width - thickness, 0, thickness, size.height),
        _ => Offset.zero & (vertical ? Size(thickness, size.height) : Size(size.width, thickness)),
      };
      final children = <Widget>[
        Positioned.fromRect(
          rect: barRect,
          child: ProgressBuilder(
            value: model.progress,
            builder: (context, p) => CustomPaint(
              painter: _BarPainter(
                progress: p,
                vertical: vertical,
                fill: palette.fill(model.tone),
                track: palette.track,
                notch: palette.bg,
                marks: showMarks ? model.marks : const [],
              ),
            ),
          ),
        ),
      ];
      if (showTime) children.add(_pill(barRect, size, vertical));
      final dotAt = switch (placement) {
        Placement.top => Offset(size.width - 10, thickness + 4),
        Placement.bottom => Offset(size.width - 10, size.height - thickness - 10),
        Placement.left => Offset(thickness + 4, 4),
        _ => Offset(size.width - thickness - 10, 4),
      };
      children.add(Positioned(
        left: dotAt.dx,
        top: dotAt.dy,
        child: LinkDot(model: model, palette: palette, tooltip: linkTooltip),
      ));
      return Stack(clipBehavior: Clip.none, children: children);
    });
  }

  Widget _pill(Rect bar, Size size, bool vertical) {
    final text = pillText(model, label);
    final style = digitsStyle(_pillFont, palette.digits(model.tone));
    final textSize = measure(text, style);
    final inside = barLabelInside(placement, thickness);
    final w = vertical ? verticalPillWidth : textSize.width + 12;
    final h = inside ? thickness - 4 : _pillHeight;
    double along(double length, double extent) {
      final end = model.hasRun ? model.progress * length : 0.0;
      return clampD(end - extent / 2, 0, length - extent);
    }

    final Rect r;
    if (vertical) {
      final y = bar.height - along(bar.height, h) - h;
      final x = placement == Placement.left ? bar.right + _pillGap : bar.left - _pillGap - w;
      r = Rect.fromLTWH(x, y, w, h);
    } else {
      final x = along(bar.width, w);
      final y = inside
          ? bar.top + 2
          : (placement == Placement.top ? bar.bottom + _pillGap : bar.top - _pillGap - h);
      r = Rect.fromLTWH(x, y, w, h);
    }
    return AnimatedPositioned.fromRect(
      rect: r,
      duration: const Duration(milliseconds: 240),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.bg,
          border: inside ? null : Border.all(color: palette.line),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.clip),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.progress,
    required this.vertical,
    required this.fill,
    required this.track,
    required this.notch,
    required this.marks,
  });

  final double progress;
  final bool vertical;
  final Color fill;
  final Color track;
  final Color notch;
  final List<double> marks;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = track);
    final filled = vertical
        ? Rect.fromLTRB(0, size.height * (1 - progress), size.width, size.height)
        : Rect.fromLTWH(0, 0, size.width * progress, size.height);
    canvas.drawRect(filled, Paint()..color = fill);
    final notchPaint = Paint()
      ..color = notch
      ..strokeWidth = 1;
    for (final m in marks) {
      if (vertical) {
        final y = size.height * (1 - m);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), notchPaint);
      } else {
        final x = size.width * m;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), notchPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.progress != progress || old.fill != fill || old.track != track || old.marks != marks;
}

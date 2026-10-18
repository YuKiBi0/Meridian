import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/display.dart';
import '../theme.dart';
import 'common.dart';

/// Padding inside the digits card for a font size.
EdgeInsets digitsPadding(double fs) => EdgeInsets.symmetric(horizontal: fs * 0.45, vertical: fs * 0.3);

double digitsSubSize(double fs) => math.max(11, fs * 0.28);

/// Size of the digits card for the current content (window follows it).
Size digitsViewSize(DisplayModel m, double fs, bool showTitle, String? label) {
  final digits = measure(m.digits, digitsStyle(fs, const Color(0xFF000000)));
  final subStyle = textStyle(digitsSubSize(fs), const Color(0xFF000000));
  var w = digits.width;
  var h = digits.height;
  final title = showTitle && m.title.isNotEmpty ? m.title : null;
  if (title != null) {
    final t = measure(title, subStyle);
    w = math.max(w, math.min(t.width, digits.width * 1.6));
    h += t.height + fs * 0.12;
  }
  if (label != null) {
    final l = measure(label, subStyle);
    w = math.max(w, l.width);
    h += l.height + fs * 0.12;
  }
  final pad = digitsPadding(fs);
  // + 1 px border on each side, + 1 px so rounding never clips.
  return Size((w + pad.horizontal + 3).ceilToDouble(), (h + pad.vertical + 3).ceilToDouble());
}

/// Just the numbers: the quietest style (PRD CLI-22).
class DigitsView extends StatelessWidget {
  const DigitsView({
    super.key,
    required this.model,
    required this.palette,
    required this.fontSize,
    required this.showTitle,
    required this.label,
    required this.linkTooltip,
  });

  final DisplayModel model;
  final Palette palette;
  final double fontSize;
  final bool showTitle;
  final String? label;
  final String linkTooltip;

  @override
  Widget build(BuildContext context) {
    final sub = textStyle(digitsSubSize(fontSize), palette.fgMuted);
    final gap = SizedBox(height: fontSize * 0.12);
    return Container(
      padding: digitsPadding(fontSize),
      decoration: BoxDecoration(
        color: palette.bg.withValues(alpha: 0.94),
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (showTitle && model.title.isNotEmpty) ...[
              Text(model.title, style: sub, maxLines: 1, overflow: TextOverflow.ellipsis),
              gap,
            ],
            Text(model.digits, style: digitsStyle(fontSize, palette.digits(model.tone)), maxLines: 1),
            if (label != null) ...[gap, Text(label!, style: sub, maxLines: 1)],
          ]),
        ),
        Positioned(
          right: -fontSize * 0.3,
          top: -fontSize * 0.18,
          child: LinkDot(model: model, palette: palette, tooltip: linkTooltip),
        ),
      ]),
    );
  }
}

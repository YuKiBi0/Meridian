import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/display.dart';
import '../theme.dart';

/// Measures a single line of text.
Size measure(String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return tp.size;
}

/// Paints [text] centered at [center], or anchored by [align].
void paintText(Canvas canvas, String text, TextStyle style, Offset at, {Alignment align = Alignment.center}) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final dx = at.dx - tp.width * (align.x + 1) / 2;
  final dy = at.dy - tp.height * (align.y + 1) / 2;
  tp.paint(canvas, Offset(dx, dy));
}

/// The small muted dot shown while reconnecting (DESIGN §5.7).
class LinkDot extends StatelessWidget {
  const LinkDot({super.key, required this.model, required this.palette, required this.tooltip});

  final DisplayModel model;
  final Palette palette;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    if (model.link == Link.connected || model.label == StatusLabel.waiting) {
      return const SizedBox.shrink();
    }
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: palette.fgMuted, shape: BoxShape.circle),
      ),
    );
  }
}

/// Text inside the pill / under the digits: the status word if there is one,
/// otherwise the remaining time.
String pillText(DisplayModel m, String? label) =>
    (m.label == StatusLabel.waiting || m.label == StatusLabel.notStarted || m.label == StatusLabel.ended)
        ? label!
        : m.digits;

double clampD(double v, double lo, double hi) => math.min(math.max(v, lo), hi);

/// Rebuilds with [value], animating over 240 ms only on visible jumps
/// (an extension or a new run). Ordinary ticking moves without animation
/// so idle frames stay idle (PRD CLI-14).
class ProgressBuilder extends StatefulWidget {
  const ProgressBuilder({super.key, required this.value, required this.builder});

  final double value;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<ProgressBuilder> createState() => _ProgressBuilderState();
}

class _ProgressBuilderState extends State<ProgressBuilder> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  late double _from = widget.value;

  @override
  void didUpdateWidget(ProgressBuilder old) {
    super.didUpdateWidget(old);
    final shown = _c.isAnimating ? _from + (old.value - _from) * _c.value : old.value;
    if ((widget.value - shown).abs() > 0.01) {
      _from = shown;
      _c.forward(from: 0);
    } else if (!_c.isAnimating) {
      _from = widget.value;
    }
  }

  double get _current => _c.isAnimating ? _from + (widget.value - _from) * _c.value : widget.value;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _c, builder: (context, _) => widget.builder(context, _current));
}

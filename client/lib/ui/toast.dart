/// Reminder cards drawn inside the window (PRD §8.6). No system
/// notifications are used.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/format.dart';
import '../core/protocol.dart';
import '../window/geometry.dart';
import 'theme.dart';

const maxToasts = 3;

class ToastItem {
  ToastItem(this.event) : shownAt = DateTime.now();

  final ReminderEvent event;
  final DateTime shownAt;
  Timer? timer;
}

class ToastController extends ChangeNotifier {
  final List<ToastItem> items = [];

  /// Shows a reminder. The server fires each reminder once per crossing and
  /// never replays missed ones, so no de-duplication is needed here.
  void show(ReminderEvent e) {
    final item = ToastItem(e);
    if (!e.sticky && e.durationMs > 0) {
      item.timer = Timer(Duration(milliseconds: e.durationMs), () => dismiss(item));
    }
    items.add(item);
    while (items.length > maxToasts) {
      items.removeAt(0).timer?.cancel();
    }
    notifyListeners();
  }

  void dismiss(ToastItem item) {
    item.timer?.cancel();
    if (items.remove(item)) notifyListeners();
  }

  @override
  void dispose() {
    for (final i in items) {
      i.timer?.cancel();
    }
    super.dispose();
  }
}

/// The cards, newest closest to the view.
class ToastStack extends StatelessWidget {
  const ToastStack({
    super.key,
    required this.controller,
    required this.side,
    required this.palette,
    required this.gotIt,
    required this.alertAtMs,
  });

  final ToastController controller;
  final ToastSide side;
  final Palette palette;
  final String gotIt;

  /// Reminder points at or below this are shown with a vermilion line.
  final int alertAtMs;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final item in controller.items)
        Padding(
          key: ObjectKey(item),
          padding: const EdgeInsets.only(bottom: toastGap),
          child: _Card(item: item, palette: palette, gotIt: gotIt, alertAtMs: alertAtMs, controller: controller, side: side),
        ),
    ];
    final ordered = side == ToastSide.above ? cards : cards.reversed.toList();
    return Column(
      mainAxisAlignment: side == ToastSide.above ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: ordered,
    );
  }
}

class _Card extends StatefulWidget {
  const _Card({
    required this.item,
    required this.palette,
    required this.gotIt,
    required this.alertAtMs,
    required this.controller,
    required this.side,
  });

  final ToastItem item;
  final Palette palette;
  final String gotIt;
  final int alertAtMs;
  final ToastController controller;
  final ToastSide side;

  @override
  State<_Card> createState() => _CardState();
}

class _CardState extends State<_Card> with SingleTickerProviderStateMixin {
  late final AnimationController _life;

  @override
  void initState() {
    super.initState();
    final e = widget.item.event;
    final ms = e.sticky || e.durationMs <= 0 ? 0 : e.durationMs;
    _life = AnimationController(vsync: this, duration: Duration(milliseconds: ms == 0 ? 1 : ms));
    if (ms > 0) _life.forward();
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Offset get _enterFrom => switch (widget.side) {
        ToastSide.below => const Offset(0, -4),
        ToastSide.above => const Offset(0, 4),
        ToastSide.right => const Offset(-4, 0),
        ToastSide.left => const Offset(4, 0),
      };

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final e = widget.item.event;
    final alert = e.atMs <= widget.alertAtMs;
    final lineColor = alert ? Palette.alert : p.fgMuted;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: _enterFrom * (1 - t), child: child),
      ),
      child: GestureDetector(
        onTap: e.sticky ? null : () => widget.controller.dismiss(widget.item),
        child: Container(
          width: toastWidth,
          height: toastCardHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: p.bg,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      e.title.isEmpty ? (e.atMs == 0 ? '00:00' : formatRemaining(e.atMs)) : e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyle(12, p.fgMuted),
                    ),
                  ),
                  if (e.sticky)
                    GestureDetector(
                      onTap: () => widget.controller.dismiss(widget.item),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text(widget.gotIt, style: textStyle(12, p.fg, weight: FontWeight.w500)),
                      ),
                    ),
                ]),
                const SizedBox(height: 4),
                Text(e.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: textStyle(15, p.fg)),
              ]),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 2,
              child: AnimatedBuilder(
                animation: _life,
                builder: (context, _) => FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: e.sticky ? 1 : 1 - _life.value,
                  child: ColoredBox(color: lineColor),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

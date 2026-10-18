import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../theme.dart';

/// Frame for the panel pages (connect, settings, about): a drag handle
/// header, since the window has no title bar.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.palette, required this.title, required this.child, this.onClose, this.closeLabel});

  final Palette palette;
  final String title;
  final Widget child;
  final VoidCallback? onClose;
  final String? closeLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.line),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => windowManager.startDragging(),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.line))),
            child: Row(children: [
              const Mark(size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: textStyle(14, palette.fg, weight: FontWeight.w500))),
              if (onClose != null) TextAction(label: closeLabel ?? '×', palette: palette, onTap: onClose!),
            ]),
          ),
        ),
        Expanded(child: child),
      ]),
    );
  }
}

/// The product mark: ring, vertical line, a dot one third down (DESIGN §4.4).
class Mark extends StatelessWidget {
  const Mark({super.key, required this.size, this.dot = Palette.accent});

  final double size;
  final Color dot;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _MarkPainter(Theme.of(context).colorScheme.onSurface, dot));
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.ink, this.dot);

  final Color ink;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final p = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * u;
    canvas.drawCircle(Offset(12 * u, 12 * u), 9 * u, p);
    canvas.drawLine(Offset(12 * u, 2 * u), Offset(12 * u, 22 * u), p);
    canvas.drawCircle(Offset(12 * u, 8.7 * u), 2 * u, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.ink != ink || old.dot != dot;
}

class TextAction extends StatelessWidget {
  const TextAction({super.key, required this.label, required this.palette, required this.onTap, this.strong = false});

  final String label;
  final Palette palette;
  final VoidCallback onTap;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Text(label, style: textStyle(13, strong ? palette.fg : palette.fgMuted, weight: strong ? FontWeight.w500 : FontWeight.w400)),
        ),
      ),
    );
  }
}

/// A row of mutually exclusive choices.
class Segmented<T> extends StatelessWidget {
  const Segmented({super.key, required this.palette, required this.value, required this.options, required this.onChanged});

  final Palette palette;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final e in options.entries)
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onChanged(e.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: e.key == value ? palette.fg : Colors.transparent,
                border: Border.all(color: e.key == value ? palette.fg : palette.line),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(e.value, style: textStyle(13, e.key == value ? palette.bg : palette.fg)),
              ),
            ),
          ),
        ),
    ]);
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.palette, this.label, required this.child});

  final Palette palette;
  final String? label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label != null) ...[
          Text(label!, style: textStyle(12, palette.fgMuted)),
          const SizedBox(height: 6),
        ],
        child,
      ]),
    );
  }
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.palette, required this.label, required this.value, required this.onChanged});

  final Palette palette;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: textStyle(14, palette.fg))),
        Transform.scale(scale: 0.8, child: Switch(value: value, onChanged: onChanged)),
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, required this.palette});

  final String text;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 4),
      padding: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.line))),
      child: Text(text, style: textStyle(13, palette.fg, weight: FontWeight.w500)),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.palette, required this.onTap});

  final String label;
  final Palette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap == null ? palette.fgMuted : palette.fg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: textStyle(14, palette.bg, weight: FontWeight.w500)),
        ),
      ),
    );
  }
}

InputDecoration inputDecoration(Palette p, String hint) => InputDecoration(
      hintText: hint,
      hintStyle: textStyle(14, p.fgMuted),
      isDense: true,
      filled: true,
      fillColor: p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: p.line), borderRadius: BorderRadius.circular(4)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: p.fgMuted), borderRadius: BorderRadius.circular(4)),
    );

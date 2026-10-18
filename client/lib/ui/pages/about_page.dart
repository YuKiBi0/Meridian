import 'package:flutter/material.dart';

import '../l10n.dart';
import '../theme.dart';
import 'widgets.dart';

/// About: the mark, the version with its solar term, and the one passage
/// where the product is allowed some character (DESIGN §4.1).
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.palette, required this.strings, required this.onClose});

  final Palette palette;
  final Strings strings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = strings;
    return Panel(
      palette: p,
      title: s.about,
      onClose: onClose,
      closeLabel: s.close,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Mark(size: 40),
          const SizedBox(height: 16),
          Text(s.appName, style: textStyle(22, p.fg, weight: FontWeight.w500)),
          Text('$appVersion · ${s.solarTerm}', style: textStyle(13, p.fgMuted)),
          const SizedBox(height: 24),
          for (final line in s.aboutText)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(line, style: textStyle(14, p.fg)),
            ),
          const Spacer(),
          Text(s.slogan, style: textStyle(14, p.fgMuted)),
          const SizedBox(height: 4),
          Text('github.com/YuKiBi0/Meridian', style: textStyle(12, p.fgMuted)),
        ]),
      ),
    );
  }
}

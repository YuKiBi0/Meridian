import 'package:flutter/material.dart';

import '../../settings.dart';
import '../l10n.dart';
import '../theme.dart';
import 'widgets.dart';

/// A display the user can pick (id and a readable name).
typedef DisplayChoice = ({String id, String name});

/// Settings shown inside the main window (PRD CLI-52).
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.palette,
    required this.strings,
    required this.settings,
    required this.displays,
    required this.onChangeAddress,
    required this.onClose,
  });

  final Palette palette;
  final Strings strings;
  final Settings settings;
  final List<DisplayChoice> displays;
  final VoidCallback onChangeAddress;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final s = strings;
    final st = settings;
    void set(void Function(Settings) f) => st.update(f);
    String px(double v) => '${v.round()} px';

    final styleOptions = <Widget>[
      switch (st.style) {
        ViewStyle.bar => SettingRow(
            palette: p,
            label: s.thickness,
            child: Segmented<double>(
              palette: p,
              value: st.barThickness,
              options: {for (final t in barThicknesses) t: px(t)},
              onChanged: (v) => set((x) => x.barThickness = v),
            ),
          ),
        ViewStyle.ring => SettingRow(
            palette: p,
            label: s.size,
            child: Segmented<SizeStep>(
              palette: p,
              value: st.ringSize,
              options: s.sizeNames,
              onChanged: (v) => set((x) => x.ringSize = v),
            ),
          ),
        ViewStyle.digits => SettingRow(
            palette: p,
            label: s.size,
            child: Segmented<SizeStep>(
              palette: p,
              value: st.digitsSize,
              options: s.sizeNames,
              onChanged: (v) => set((x) => x.digitsSize = v),
            ),
          ),
        ViewStyle.ruler => SettingRow(
            palette: p,
            label: s.height,
            child: Segmented<double>(
              palette: p,
              value: st.rulerHeight,
              options: {for (final h in rulerHeights) h: px(h)},
              onChanged: (v) => set((x) => x.rulerHeight = v),
            ),
          ),
      },
      if (st.style == ViewStyle.bar)
        SwitchRow(palette: p, label: s.showTime, value: st.barShowTime, onChanged: (v) => set((x) => x.barShowTime = v)),
      if (st.style == ViewStyle.digits)
        SwitchRow(
            palette: p, label: s.showTitle, value: st.digitsShowTitle, onChanged: (v) => set((x) => x.digitsShowTitle = v)),
      if (st.style == ViewStyle.bar || st.style == ViewStyle.ring)
        SwitchRow(palette: p, label: s.showMarks, value: st.showMarks, onChanged: (v) => set((x) => x.showMarks = v)),
    ];

    return Panel(
      palette: p,
      title: s.settings,
      onClose: onClose,
      closeLabel: s.close,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          SectionTitle(s.connection, palette: p),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Expanded(
                child: Text(st.address ?? '—',
                    style: textStyle(14, p.fg), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              TextAction(label: s.change, palette: p, onTap: onChangeAddress, strong: true),
            ]),
          ),
          SectionTitle(s.style, palette: p),
          SettingRow(
            palette: p,
            child: Segmented<ViewStyle>(
              palette: p,
              value: st.style,
              options: s.styleNames,
              onChanged: (v) => set((x) => x.style = v),
            ),
          ),
          ...styleOptions,
          SectionTitle(s.snap, palette: p),
          SettingRow(
            palette: p,
            child: Segmented<Placement>(
              palette: p,
              value: st.currentPlacement,
              options: {for (final pl in placementsFor[st.style]!) pl: s.placementNames[pl]!},
              onChanged: (v) => set((x) => x.placement[x.style] = v),
            ),
          ),
          SettingRow(
            palette: p,
            label: s.margin,
            child: Segmented<double>(
              palette: p,
              value: st.margin,
              options: {for (final m in margins) m: px(m)},
              onChanged: (v) => set((x) => x.margin = v),
            ),
          ),
          if (displays.isNotEmpty)
            SettingRow(
              palette: p,
              label: s.display,
              child: Segmented<String?>(
                palette: p,
                value: displays.any((d) => d.id == st.displayId) ? st.displayId : null,
                options: {null: s.primaryDisplay, for (final d in displays) d.id: d.name},
                onChanged: (v) => set((x) => x.displayId = v),
              ),
            ),
          SectionTitle(s.window, palette: p),
          SwitchRow(palette: p, label: s.alwaysOnTop, value: st.alwaysOnTop, onChanged: (v) => set((x) => x.alwaysOnTop = v)),
          SwitchRow(palette: p, label: s.clickThrough, value: st.clickThrough, onChanged: (v) => set((x) => x.clickThrough = v)),
          SwitchRow(
              palette: p, label: s.launchAtStartup, value: st.launchAtStartup, onChanged: (v) => set((x) => x.launchAtStartup = v)),
          SettingRow(
            palette: p,
            label: '${s.opacity} ${(st.opacity * 100).round()}%',
            child: Slider(
              value: st.opacity,
              min: 0.4,
              max: 1,
              divisions: 12,
              onChanged: (v) => set((x) => x.opacity = v),
            ),
          ),
          SectionTitle(s.appearance, palette: p),
          SettingRow(
            palette: p,
            child: Segmented<ThemeChoice>(
              palette: p,
              value: st.theme,
              options: s.themeNames,
              onChanged: (v) => set((x) => x.theme = v),
            ),
          ),
          SettingRow(
            palette: p,
            label: s.language,
            child: Segmented<LangChoice>(
              palette: p,
              value: st.lang,
              options: s.langNames,
              onChanged: (v) => set((x) => x.lang = v),
            ),
          ),
        ],
      ),
    );
  }
}

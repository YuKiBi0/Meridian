/// Tray icon and the menu shared by the tray and the window (PRD §8.5).
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart' show Menu, MenuItem, trayManager;

import '../core/display.dart';
import '../settings.dart';
import 'colors.dart';
import 'l10n.dart';
import 'theme.dart';
import 'tray_icon.dart';

enum TrayDot { hollow, solid, running, alert }

TrayDot trayDotFor(DisplayModel m, bool everConnected) {
  if (!everConnected || m.link == Link.disconnected) return TrayDot.hollow;
  return switch (m.tone) {
    Tone.live => TrayDot.running,
    Tone.alert => m.hasRun ? TrayDot.alert : TrayDot.solid,
    Tone.muted => TrayDot.solid,
  };
}

/// Menu item keys.
abstract final class MenuKeys {
  static const stylePrefix = 'style:';
  static const placePrefix = 'place:';
  static const topmost = 'topmost';
  static const clickThrough = 'click';
  static const settings = 'settings';
  static const about = 'about';
  static const quit = 'quit';
}

class Tray {
  String? _icon;
  int _iconRequest = 0;
  String? _tooltip;
  String? _menuSignature;

  /// Sets the icon for [dot]; the body follows the taskbar brightness and a
  /// running dot takes the progress colour [accent].
  Future<void> setIcon(TrayDot dot, Brightness brightness, Color accent) async {
    final request = ++_iconRequest;
    if (Platform.isMacOS) return _setMenuBarIcon(request, dot, brightness, accent);
    final theme = brightness == Brightness.dark ? 'paper' : 'ink';
    var path = 'assets/tray/${dot.name}_$theme.ico';
    if (dot == TrayDot.running && accent != defaultAccent) {
      try {
        // An absolute path: tray_manager joins it onto flutter_assets.
        path = await runningIconFile(accent, brightness);
      } catch (_) {
        // Keep the bundled amber icon.
      }
    }
    if (request != _iconRequest || path == _icon) return; // superseded or unchanged
    _icon = path;
    await trayManager.setIcon(path);
  }

  /// trayManager.setIcon only takes bundled assets on macOS, so this sends
  /// the drawn icon the way it does (tray_manager 0.5, TrayManagerPlugin.swift).
  Future<void> _setMenuBarIcon(int request, TrayDot dot, Brightness brightness, Color accent) async {
    final p = brightness == Brightness.dark ? Palette.dark : Palette.light;
    final key = '${dot.name}:${p.fg.toARGB32()}:${accent.toARGB32()}';
    if (key == _icon) return;
    final png = await switch (dot) {
      TrayDot.hollow => menuBarIcon(p.fg, p.fg, hole: p.bg),
      TrayDot.solid => menuBarIcon(p.fg, p.fg),
      TrayDot.running => menuBarIcon(p.fg, accent),
      TrayDot.alert => menuBarIcon(p.fg, Palette.alert),
    };
    if (request != _iconRequest) return; // superseded
    _icon = key;
    await const MethodChannel('tray_manager').invokeMethod('setIcon', {
      'id': key,
      'iconPath': '',
      'base64Icon': base64Encode(png),
      'isTemplate': false,
      'iconPosition': 'left',
      'iconSize': 18,
    });
  }

  Future<void> setTooltip(String text) async {
    if (text == _tooltip) return;
    _tooltip = text;
    await trayManager.setToolTip(text);
  }

  Future<void> setMenu(Settings s, Strings t) async {
    final placements = placementsFor[s.style]!;
    final signature = [
      t.appName,
      s.style,
      s.currentPlacement,
      s.alwaysOnTop,
      s.clickThrough,
    ].join('|');
    if (signature == _menuSignature) return;
    _menuSignature = signature;
    await trayManager.setContextMenu(Menu(items: [
      MenuItem.submenu(
        label: t.style,
        submenu: Menu(items: [
          for (final v in ViewStyle.values)
            MenuItem.checkbox(key: '${MenuKeys.stylePrefix}${v.name}', label: t.styleNames[v], checked: s.style == v),
        ]),
      ),
      MenuItem.submenu(
        label: t.snap,
        submenu: Menu(items: [
          for (final p in placements)
            MenuItem.checkbox(
              key: '${MenuKeys.placePrefix}${p.name}',
              label: t.placementNames[p],
              checked: s.currentPlacement == p,
            ),
        ]),
      ),
      MenuItem.checkbox(key: MenuKeys.topmost, label: t.alwaysOnTop, checked: s.alwaysOnTop),
      MenuItem.checkbox(key: MenuKeys.clickThrough, label: t.clickThrough, checked: s.clickThrough),
      MenuItem.separator(),
      MenuItem(key: MenuKeys.settings, label: '${t.settings}…'),
      MenuItem(key: MenuKeys.about, label: t.about),
      MenuItem.separator(),
      MenuItem(key: MenuKeys.quit, label: t.quit),
    ]));
  }

  Future<void> popUp() => trayManager.popUpContextMenu();

  Future<void> destroy() => trayManager.destroy();
}

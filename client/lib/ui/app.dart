/// The application shell: switches between the connect page, the
/// countdown view and the panels, and keeps the window where it belongs.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:tray_manager/tray_manager.dart' show MenuItem, TrayListener, trayManager;
import 'package:window_manager/window_manager.dart';

import '../core/address.dart';
import '../core/connection.dart';
import '../core/countdown.dart';
import '../core/display.dart';
import '../core/format.dart';
import '../settings.dart';
import '../window/geometry.dart';
import '../window/window_controller.dart';
import 'l10n.dart';
import 'pages/about_page.dart';
import 'pages/connect_page.dart';
import 'pages/settings_page.dart';
import 'styles/bar.dart';
import 'styles/digits.dart';
import 'styles/ring.dart';
import 'styles/ruler.dart';
import 'theme.dart';
import 'toast.dart';
import 'tray.dart';

enum AppMode { connect, view, settings, about }

const _panelSizes = {
  AppMode.connect: Size(420, 300),
  AppMode.settings: Size(420, 600),
  AppMode.about: Size(420, 440),
};

class MeridianApp extends StatefulWidget {
  const MeridianApp({
    super.key,
    required this.settings,
    required this.connection,
    required this.window,
  });

  final Settings settings;
  final ServerConnection connection;
  final WindowController window;

  @override
  State<MeridianApp> createState() => _MeridianAppState();
}

class _MeridianAppState extends State<MeridianApp> with WindowListener, TrayListener, WidgetsBindingObserver {
  final _toasts = ToastController();
  final _tray = Tray();
  StreamSubscription<Object?>? _reminderSub;

  late AppMode _mode;
  AppMode _returnTo = AppMode.view;
  List<Monitor> _monitors = const [];
  Layout? _layout;
  Size? _viewSize;

  Timer? _tick;
  Timer? _guard;
  Timer? _wake;
  DateTime _lastWall = DateTime.now();
  bool _relayoutQueued = false;

  Settings get _s => widget.settings;
  ServerConnection get _conn => widget.connection;
  Countdown get _countdown => _conn.countdown;
  WindowController get _win => widget.window;

  Strings get _t => Strings.of(_s.lang);

  Brightness get _systemBrightness => WidgetsBinding.instance.platformDispatcher.platformBrightness;

  Palette get _palette => switch (_s.theme) {
        ThemeChoice.light => Palette.light,
        ThemeChoice.dark => Palette.dark,
        ThemeChoice.system => _systemBrightness == Brightness.dark ? Palette.dark : Palette.light,
      }.withAccent(Color(_s.accentColor));

  DisplayModel get _model => DisplayModel.from(_countdown, _conn.link, everConnected: _conn.everConnected);

  // ---- lifecycle ----

  @override
  void initState() {
    super.initState();
    final address = _s.address == null ? null : RoomAddress.parse(_s.address!);
    _mode = address == null ? AppMode.connect : AppMode.view;
    // An address saved by 1.0 has no room.
    if (_s.address != null && address == null) _addressError = _t.missingRoom;
    if (address != null) _conn.connect(address, roomName: _s.roomName);

    _conn.addListener(_onConnection);
    _s.addListener(_onSettings);
    _toasts.addListener(_onToasts);
    _reminderSub = _conn.reminders.listen(_toasts.show);
    windowManager.addListener(this);
    trayManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);

    _guard = Timer.periodic(const Duration(seconds: 5), (_) => _guardTick());
    _wake = Timer.periodic(const Duration(seconds: 2), (_) => _wakeTick());
    _boot();
  }

  Future<void> _boot() async {
    _monitors = await _win.monitors();
    await _applyLaunchAtStartup();
    _syncTray();
    _relayout();
    _scheduleTick();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _guard?.cancel();
    _wake?.cancel();
    _reminderSub?.cancel();
    _conn.removeListener(_onConnection);
    _s.removeListener(_onSettings);
    _toasts.removeListener(_onToasts);
    _toasts.dispose();
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ---- reactions ----

  void _onConnection() {
    if (_conn.roomGone && !_leftRoom) {
      // PRD CLI-03: back to the address page when the room is deleted.
      _leftRoom = true;
      _pendingConnect = false;
      _addressError = _t.roomDeleted;
      _toasts.clear();
      _mode = AppMode.connect;
      _relayout();
    }
    final name = _conn.roomName;
    if (name != null && name != _s.roomName && !_conn.roomGone) {
      _s.update((s) => s.roomName = name);
    }
    if (_mode == AppMode.connect && _conn.everConnected && _pendingConnect) {
      _pendingConnect = false;
      _mode = AppMode.view;
      _relayout();
    }
    _refresh();
  }

  void _onSettings() {
    _syncTray();
    _win.setTitle(_t.appName);
    _applyLaunchAtStartup();
    _relayout();
    _refresh();
  }

  void _onToasts() {
    _relayout();
    setState(() {});
  }

  /// Redraws and reschedules the next tick.
  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _syncTray();
    _checkViewSize();
    _scheduleTick();
  }

  void _scheduleTick() {
    _tick?.cancel();
    final ms = _countdown.nextChangeInMs(_pixelSpan());
    if (ms == null) return;
    _tick = Timer(Duration(milliseconds: ms + 1), _refresh);
  }

  /// Device pixels across which progress is drawn (for CLI-14).
  double _pixelSpan() {
    final v = _layout?.view;
    if (v == null || _mode != AppMode.view) return 0;
    final scale = WindowController.pick(_monitors, _s.displayId).scale;
    return switch (_s.style) {
      ViewStyle.bar => (isVerticalPlacement(_s.currentPlacement) ? v.height : v.width) * scale,
      ViewStyle.ring => math.pi * v.width * scale,
      ViewStyle.ruler => v.width * scale,
      ViewStyle.digits => 0,
    };
  }

  /// The digits style changes size with its content (e.g. 59:59 → 1:00:00).
  void _checkViewSize() {
    if (_mode == AppMode.view && _s.style == ViewStyle.digits && _currentViewSize() != _viewSize) {
      _relayout();
    }
  }

  void _guardTick() {
    if (_mode == AppMode.view && _s.alwaysOnTop) _win.setTopmost(true, force: true);
    _win.monitors().then((ms) {
      if (ms.map((m) => m.signature).join() != _monitors.map((m) => m.signature).join()) {
        _monitors = ms;
        _relayout();
      }
    });
  }

  /// PRD CLI-15: a long gap between ticks means the PC slept.
  void _wakeTick() {
    final now = DateTime.now();
    if (now.difference(_lastWall) > const Duration(seconds: 6)) {
      _conn.reconnect();
      _guardTick();
    }
    _lastWall = now;
  }

  Future<void> _applyLaunchAtStartup() async {
    if (!Platform.isWindows) return;
    try {
      launchAtStartup.setup(appName: 'Meridian', appPath: Platform.resolvedExecutable);
      final on = await launchAtStartup.isEnabled();
      if (on != _s.launchAtStartup) {
        _s.launchAtStartup ? await launchAtStartup.enable() : await launchAtStartup.disable();
      }
    } catch (_) {
      // Registry not writable; leave it.
    }
  }

  // ---- layout ----

  Size _currentViewSize() {
    final work = WindowController.pick(_monitors, _s.displayId).logicalWork;
    final m = _s.margin;
    final model = _model;
    switch (_s.style) {
      case ViewStyle.bar:
        final p = _s.currentPlacement;
        final cross = barCrossSize(p, _s.barThickness, _s.barShowTime);
        return isVerticalPlacement(p) ? Size(cross, work.height - 2 * m) : Size(work.width - 2 * m, cross);
      case ViewStyle.ring:
        return Size.square(ringDiameter(_s.ringSize));
      case ViewStyle.digits:
        return digitsViewSize(model, digitsFontSize(_s.digitsSize), _s.digitsShowTitle, _t.label(model.label));
      case ViewStyle.ruler:
        return Size(work.width - 2 * m, _s.rulerHeight);
    }
  }

  /// Coalesces layout requests into one per frame.
  void _relayout() {
    if (_relayoutQueued) return;
    _relayoutQueued = true;
    scheduleMicrotask(() async {
      _relayoutQueued = false;
      await _applyLayout();
    });
  }

  Future<void> _applyLayout() async {
    if (_monitors.isEmpty) return;
    final monitor = WindowController.pick(_monitors, _s.displayId);
    final work = monitor.logicalWork;
    if (_mode != AppMode.view) {
      final size = _panelSizes[_mode]!;
      await _win.setClickThrough(false);
      await _win.setOpacity(1);
      await _win.setNoActivate(false);
      await _win.setSkipTaskbar(false);
      await _win.setTopmost(_s.alwaysOnTop);
      await _win.setBounds(Rect.fromCenter(center: work.center, width: size.width, height: size.height), monitor);
      await _win.focus();
      if (mounted) setState(() => _layout = null);
      return;
    }
    final viewSize = _currentViewSize();
    final free = _s.freePosition[_s.style];
    final layout = layoutFor(
      work: work,
      placement: _s.currentPlacement,
      viewSize: viewSize,
      margin: _s.margin,
      free: free == null ? null : work.topLeft + Offset(free.x, free.y),
      toasts: _toasts.items.length,
    );
    _viewSize = viewSize;
    if (mounted) setState(() => _layout = layout);
    await _win.setBounds(layout.window, monitor);
    await _win.setNoActivate(true);
    await _win.setSkipTaskbar(true);
    await _win.setTopmost(_s.alwaysOnTop);
    // Reminder cards stay clickable even in click-through mode (CLI-65).
    await _win.setClickThrough(_s.clickThrough && _toasts.items.isEmpty);
    await _win.setOpacity(_s.opacity);
    _scheduleTick();
  }

  // ---- window events ----

  bool _pendingConnect = false;

  /// Why the connect page is shown, if not first run: the saved address has
  /// no room, or the room was deleted.
  String? _addressError;
  bool _leftRoom = false;

  bool get _draggable => _mode == AppMode.view && (_s.style == ViewStyle.ring || _s.style == ViewStyle.digits);

  @override
  void onWindowMoved() => _afterDrag();

  Future<void> _afterDrag() async {
    if (!_draggable || _layout == null) return;
    final b = await _win.bounds();
    if (b == null) return;
    final monitor = WindowController.pick(_monitors, _s.displayId);
    final work = monitor.logicalWork;
    final origin = Offset(b.left / monitor.scale, b.top / monitor.scale) + _layout!.view.topLeft;
    final view = origin & _layout!.view.size;
    final snapped = snapPlacement(view, work, placementsFor[_s.style]!, _s.margin);
    _s.update((s) {
      s.placement[s.style] = snapped;
      if (snapped == Placement.free) {
        final rel = view.topLeft - work.topLeft;
        s.freePosition[s.style] = (x: rel.dx, y: rel.dy);
      }
    });
  }

  @override
  void didChangeMetrics() => _relayout();

  @override
  void didChangePlatformBrightness() => _onSettings();

  // ---- tray ----

  void _syncTray() {
    final model = _model;
    _tray.setIcon(trayDotFor(model, _conn.everConnected), _systemBrightness, Color(_s.accentColor));
    _tray.setMenu(_s, _t);
    final label = _t.label(model.label);
    final tip = !_conn.everConnected
        ? '${_t.appName} · ${_t.link(_conn.link)}'
        : [if (model.title.isNotEmpty) model.title, label ?? model.digits].join(' · ');
    _tray.setTooltip(tip.isEmpty ? _t.appName : tip);
  }

  @override
  void onTrayIconMouseDown() => _tray.popUp();

  @override
  void onTrayIconRightMouseDown() => _tray.popUp();

  @override
  void onTrayMenuItemClick(MenuItem item) {
    final key = item.key ?? '';
    if (key.startsWith(MenuKeys.stylePrefix)) {
      final v = ViewStyle.values.byName(key.substring(MenuKeys.stylePrefix.length));
      _s.update((s) => s.style = v);
    } else if (key.startsWith(MenuKeys.placePrefix)) {
      final v = Placement.values.byName(key.substring(MenuKeys.placePrefix.length));
      _s.update((s) => s.placement[s.style] = v);
    } else if (key == MenuKeys.topmost) {
      _s.update((s) => s.alwaysOnTop = !s.alwaysOnTop);
    } else if (key == MenuKeys.clickThrough) {
      _s.update((s) => s.clickThrough = !s.clickThrough);
    } else if (key == MenuKeys.settings) {
      _openPanel(AppMode.settings);
    } else if (key == MenuKeys.about) {
      _openPanel(AppMode.about);
    } else if (key == MenuKeys.quit) {
      _quit();
    }
  }

  /// Whether the connect page can be closed: only with a room to go back to.
  bool get _canLeaveConnect => _s.address != null && _addressError == null;

  void _openPanel(AppMode mode) {
    if (_mode == AppMode.connect && !_canLeaveConnect) return;
    _returnTo = _mode == AppMode.settings ? AppMode.settings : AppMode.view;
    setState(() => _mode = mode);
    _relayout();
  }

  void _closePanel() {
    setState(() => _mode = _mode == AppMode.connect ? _returnTo : AppMode.view);
    _relayout();
  }

  Future<void> _quit() async {
    await _tray.destroy();
    await _win.quit();
  }

  void _connect(RoomAddress address, String roomName) {
    _pendingConnect = true;
    _addressError = null;
    _leftRoom = false;
    _s.update((s) {
      s.address = address.display;
      s.roomName = roomName;
    });
    _conn.connect(address, roomName: roomName);
  }

  // ---- build ----

  Widget _styleView(DisplayModel model, Palette p) {
    final label = _t.label(model.label);
    final linkTip = _t.link(model.link);
    return switch (_s.style) {
      ViewStyle.bar => BarView(
          model: model,
          placement: _s.currentPlacement,
          thickness: _s.barThickness,
          showTime: _s.barShowTime,
          showMarks: _s.showMarks,
          palette: p,
          label: label,
          linkTooltip: linkTip,
        ),
      ViewStyle.ring => RingView(model: model, palette: p, label: label, showMarks: _s.showMarks, linkTooltip: linkTip),
      ViewStyle.digits => DigitsView(
          model: model,
          palette: p,
          fontSize: digitsFontSize(_s.digitsSize),
          showTitle: _s.digitsShowTitle,
          label: label,
          linkTooltip: linkTip,
        ),
      ViewStyle.ruler => RulerView(
          model: model,
          totalMs: _countdown.state.totalMs,
          placement: _s.currentPlacement,
          palette: p,
          label: label,
          linkTooltip: linkTip,
        ),
    };
  }

  Widget _view(Palette p) {
    final layout = _layout;
    if (layout == null) return const SizedBox.shrink();
    final model = _model;
    return Stack(children: [
      Positioned.fromRect(
        rect: layout.view,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _draggable ? (_) => _win.startDragging() : null,
          onSecondaryTapUp: (_) => _tray.popUp(),
          onDoubleTap: () => _openPanel(AppMode.settings),
          child: _styleView(model, p),
        ),
      ),
      if (layout.toast != null)
        Positioned.fromRect(
          rect: layout.toast!,
          child: ToastStack(
            controller: _toasts,
            side: layout.toastSide,
            palette: p,
            gotIt: _t.gotIt,
            alertAtMs: alertThresholdMs(_countdown.state.totalMs),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = _palette;
    final t = _t;
    final Widget body = switch (_mode) {
      AppMode.view => _view(p),
      AppMode.connect => ConnectPage(
          // A new reason to be here starts the page over.
          key: ValueKey(_addressError),
          palette: p,
          strings: t,
          connection: _conn,
          initial: _s.address,
          initialError: _addressError,
          onConnect: _connect,
          onClose: _canLeaveConnect ? _closePanel : null,
        ),
      AppMode.settings => SettingsPage(
          palette: p,
          strings: t,
          settings: _s,
          roomName: _conn.roomName ?? _s.roomName,
          displays: [
            for (final (i, m) in _monitors.indexed)
              if (!m.primary) (id: m.id, name: '${t.display} ${i + 1}'),
          ],
          onChangeAddress: () {
            _returnTo = AppMode.settings;
            setState(() => _mode = AppMode.connect);
            _relayout();
          },
          onClose: _closePanel,
        ),
      AppMode.about => AboutPage(palette: p, strings: t, onClose: _closePanel),
    };
    return MaterialApp(
      title: t.appName,
      debugShowCheckedModeBanner: false,
      color: const Color(0x00000000),
      theme: themeData(p),
      home: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(style: textStyle(14, p.fg), child: body),
      ),
    );
  }
}

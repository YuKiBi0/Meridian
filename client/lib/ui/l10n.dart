/// Interface strings (DESIGN §3.4). Chinese and English never mix.
library;

import 'dart:io';

import '../core/display.dart';
import '../settings.dart';

class Strings {
  const Strings._({
    required this.appName,
    required this.serverAddress,
    required this.addressHint,
    required this.connect,
    required this.cannotConnect,
    required this.badAddress,
    required this.connected,
    required this.connecting,
    required this.disconnected,
    required this.waiting,
    required this.notStarted,
    required this.paused,
    required this.timesUp,
    required this.ended,
    required this.gotIt,
    required this.style,
    required this.styleNames,
    required this.snap,
    required this.placementNames,
    required this.alwaysOnTop,
    required this.clickThrough,
    required this.settings,
    required this.about,
    required this.quit,
    required this.close,
    required this.change,
    required this.size,
    required this.sizeNames,
    required this.thickness,
    required this.height,
    required this.showTime,
    required this.showTitle,
    required this.showMarks,
    required this.margin,
    required this.display,
    required this.primaryDisplay,
    required this.window,
    required this.opacity,
    required this.launchAtStartup,
    required this.appearance,
    required this.themeNames,
    required this.language,
    required this.langNames,
    required this.connection,
    required this.aboutText,
    required this.slogan,
    required this.solarTerm,
  });

  final String appName;
  final String serverAddress;
  final String addressHint;
  final String connect;
  final String cannotConnect;
  final String badAddress;
  final String connected;
  final String connecting;
  final String disconnected;
  final String waiting;
  final String notStarted;
  final String paused;
  final String timesUp;
  final String ended;
  final String gotIt;
  final String style;
  final Map<ViewStyle, String> styleNames;
  final String snap;
  final Map<Placement, String> placementNames;
  final String alwaysOnTop;
  final String clickThrough;
  final String settings;
  final String about;
  final String quit;
  final String close;
  final String change;
  final String size;
  final Map<SizeStep, String> sizeNames;
  final String thickness;
  final String height;
  final String showTime;
  final String showTitle;
  final String showMarks;
  final String margin;
  final String display;
  final String primaryDisplay;
  final String window;
  final String opacity;
  final String launchAtStartup;
  final String appearance;
  final Map<ThemeChoice, String> themeNames;
  final String language;
  final Map<LangChoice, String> langNames;
  final String connection;
  final List<String> aboutText;
  final String slogan;
  final String solarTerm;

  String? label(StatusLabel l) => switch (l) {
        StatusLabel.none => null,
        StatusLabel.waiting => waiting,
        StatusLabel.notStarted => notStarted,
        StatusLabel.paused => paused,
        StatusLabel.timesUp => timesUp,
        StatusLabel.ended => ended,
      };

  String link(Link l) => switch (l) {
        Link.connected => connected,
        Link.connecting => connecting,
        Link.disconnected => disconnected,
      };

  static const zh = Strings._(
    appName: '子午',
    serverAddress: '服务器地址',
    addressHint: 'https://example/meridian',
    connect: '连接',
    cannotConnect: '连不上这个地址。检查地址是否正确，或服务器是否在运行。',
    badAddress: '这不是一个有效的地址。',
    connected: '已连接',
    connecting: '连接中',
    disconnected: '未连接',
    waiting: '等待信号',
    notStarted: '未开始',
    paused: '已暂停',
    timesUp: '时间到',
    ended: '已结束',
    gotIt: '知道了',
    style: '样式',
    styleNames: {ViewStyle.bar: '条形', ViewStyle.ring: '圆环', ViewStyle.digits: '数字', ViewStyle.ruler: '刻度'},
    snap: '贴边',
    placementNames: {
      Placement.top: '上',
      Placement.bottom: '下',
      Placement.left: '左',
      Placement.right: '右',
      Placement.topLeft: '左上',
      Placement.topRight: '右上',
      Placement.bottomLeft: '左下',
      Placement.bottomRight: '右下',
      Placement.topCenter: '上中',
      Placement.bottomCenter: '下中',
      Placement.free: '自由摆放',
    },
    alwaysOnTop: '窗口置顶',
    clickThrough: '鼠标穿透',
    settings: '设置',
    about: '关于',
    quit: '退出',
    close: '关闭',
    change: '修改',
    size: '大小',
    sizeNames: {SizeStep.small: '小', SizeStep.medium: '中', SizeStep.large: '大'},
    thickness: '粗细',
    height: '高度',
    showTime: '显示剩余时间',
    showTitle: '显示标题',
    showMarks: '显示提醒刻痕',
    margin: '边距',
    display: '显示器',
    primaryDisplay: '主显示器',
    window: '窗口',
    opacity: '不透明度',
    launchAtStartup: '开机启动',
    appearance: '外观',
    themeNames: {ThemeChoice.system: '跟随系统', ThemeChoice.light: '浅色', ThemeChoice.dark: '深色'},
    language: '语言',
    langNames: {LangChoice.system: '跟随系统', LangChoice.zh: '中文', LangChoice.en: 'English'},
    connection: '连接',
    aboutText: [
      '子午线是一条人为画出来的线。',
      '不同地方的人约好同一条线，才共享同一个「现在」。',
      '这个程序只做一件事：让每个窗口都同意现在是几点。',
    ],
    slogan: '所有窗口，同一个现在。',
    solarTerm: '春分',
  );

  static const en = Strings._(
    appName: 'Meridian',
    serverAddress: 'Server address',
    addressHint: 'https://example/meridian',
    connect: 'Connect',
    cannotConnect: "Can't reach this address. Check that it is correct and the server is running.",
    badAddress: 'This is not a valid address.',
    connected: 'Connected',
    connecting: 'Connecting',
    disconnected: 'Disconnected',
    waiting: 'Waiting for signal',
    notStarted: 'Not started',
    paused: 'Paused',
    timesUp: "Time's up",
    ended: 'Ended',
    gotIt: 'Got it',
    style: 'Style',
    styleNames: {ViewStyle.bar: 'Bar', ViewStyle.ring: 'Ring', ViewStyle.digits: 'Digits', ViewStyle.ruler: 'Ruler'},
    snap: 'Snap to edge',
    placementNames: {
      Placement.top: 'Top',
      Placement.bottom: 'Bottom',
      Placement.left: 'Left',
      Placement.right: 'Right',
      Placement.topLeft: 'Top left',
      Placement.topRight: 'Top right',
      Placement.bottomLeft: 'Bottom left',
      Placement.bottomRight: 'Bottom right',
      Placement.topCenter: 'Top center',
      Placement.bottomCenter: 'Bottom center',
      Placement.free: 'Free position',
    },
    alwaysOnTop: 'Always on top',
    clickThrough: 'Click-through',
    settings: 'Settings',
    about: 'About',
    quit: 'Quit',
    close: 'Close',
    change: 'Change',
    size: 'Size',
    sizeNames: {SizeStep.small: 'S', SizeStep.medium: 'M', SizeStep.large: 'L'},
    thickness: 'Thickness',
    height: 'Height',
    showTime: 'Show remaining time',
    showTitle: 'Show title',
    showMarks: 'Show reminder marks',
    margin: 'Margin',
    display: 'Display',
    primaryDisplay: 'Primary display',
    window: 'Window',
    opacity: 'Opacity',
    launchAtStartup: 'Launch at startup',
    appearance: 'Appearance',
    themeNames: {ThemeChoice.system: 'System', ThemeChoice.light: 'Light', ThemeChoice.dark: 'Dark'},
    language: 'Language',
    langNames: {LangChoice.system: 'System', LangChoice.zh: '中文', LangChoice.en: 'English'},
    connection: 'Connection',
    aboutText: [
      'A meridian is a line someone drew.',
      'People in different places agree on the same line, and so share the same "now".',
      'This program does one thing: make every window agree on what time it is.',
    ],
    slogan: 'Every window, the same now.',
    solarTerm: 'Spring Equinox',
  );

  static Strings of(LangChoice choice) => switch (choice) {
        LangChoice.zh => zh,
        LangChoice.en => en,
        LangChoice.system => Platform.localeName.toLowerCase().startsWith('zh') ? zh : en,
      };
}

/// Shown on the about page next to the solar term.
const appVersion = 'v0.4';

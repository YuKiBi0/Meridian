/// Interface strings (DESIGN §3.4). Chinese and English never mix.
library;

import 'dart:io';

import '../core/display.dart';
import '../settings.dart';
import 'colors.dart';

class Strings {
  const Strings._({
    required this.appName,
    required this.serverAddress,
    required this.addressHint,
    required this.connect,
    required this.cannotConnect,
    required this.badAddress,
    required this.missingRoom,
    required this.roomNotFound,
    required this.roomDeleted,
    required this.room,
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
    required this.progressColor,
    required this.accentNames,
    required this.customColor,
    required this.badHex,
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
  final String missingRoom;
  final String roomNotFound;
  final String roomDeleted;
  final String room;
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
  final String progressColor;
  final Map<AccentPreset, String> accentNames;
  final String customColor;
  final String badHex;
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
    serverAddress: '房间地址',
    addressHint: 'https://example/meridian?r=…',
    connect: '连接',
    cannotConnect: '连不上这个地址。检查地址是否正确，或服务器是否在运行。',
    badAddress: '这不是一个有效的地址。',
    missingRoom: '地址里缺少房间号。在控制台进入房间，复制那里的客户端地址。',
    roomNotFound: '这个房间不存在。检查地址，或在控制台复制最新的客户端地址。',
    roomDeleted: '这个房间已被删除。填写新的房间地址。',
    room: '房间',
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
    progressColor: '进度颜色',
    accentNames: {
      AccentPreset.amber: '琥珀',
      AccentPreset.pine: '松绿',
      AccentPreset.celadon: '青瓷',
      AccentPreset.sky: '天青',
      AccentPreset.indigo: '靛蓝',
      AccentPreset.wisteria: '藤紫',
      AccentPreset.rouge: '胭脂',
      AccentPreset.moss: '苔绿',
    },
    customColor: '自定义',
    badHex: '请输入 6 位十六进制颜色，如 #3A7BD5',
    language: '语言',
    langNames: {LangChoice.system: '跟随系统', LangChoice.zh: '中文', LangChoice.en: 'English'},
    connection: '连接',
    aboutText: [
      '子午线是一条人为画出来的线。',
      '不同地方的人约好同一条线，才共享同一个「现在」。',
      '这个程序只做一件事：让每个窗口都统一现在是几点。',
    ],
    slogan: '所有窗口，同一个现在。',
    solarTerm: '小满',
  );

  static const en = Strings._(
    appName: 'Meridian',
    serverAddress: 'Room address',
    addressHint: 'https://example/meridian?r=…',
    connect: 'Connect',
    cannotConnect: "Can't reach this address. Check that it is correct and the server is running.",
    badAddress: 'This is not a valid address.',
    missingRoom: 'The address has no room. Open the room in the console and copy its client address.',
    roomNotFound: 'This room does not exist. Check the address, or copy the latest client address from the console.',
    roomDeleted: 'This room was deleted. Enter the address of another room.',
    room: 'Room',
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
    progressColor: 'Progress colour',
    accentNames: {
      AccentPreset.amber: 'Amber',
      AccentPreset.pine: 'Pine',
      AccentPreset.celadon: 'Celadon',
      AccentPreset.sky: 'Sky',
      AccentPreset.indigo: 'Indigo',
      AccentPreset.wisteria: 'Wisteria',
      AccentPreset.rouge: 'Rouge',
      AccentPreset.moss: 'Moss',
    },
    customColor: 'Custom',
    badHex: 'Enter a 6-digit hex colour, e.g. #3A7BD5',
    language: 'Language',
    langNames: {LangChoice.system: 'System', LangChoice.zh: '中文', LangChoice.en: 'English'},
    connection: 'Connection',
    aboutText: [
      'A meridian is a line someone drew.',
      'People in different places agree on the same line, and so share the same "now".',
      'This program does one thing: make every window agree on what time it is.',
    ],
    slogan: 'Every window, the same now.',
    solarTerm: 'Grain Buds',
  );

  static Strings of(LangChoice choice) => switch (choice) {
        LangChoice.zh => zh,
        LangChoice.en => en,
        LangChoice.system => Platform.localeName.toLowerCase().startsWith('zh') ? zh : en,
      };
}

/// Shown on the about page next to the solar term.
const appVersion = 'v1.0.0';

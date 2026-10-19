import Cocoa
import FlutterMacOS
import ServiceManagement

/// A borderless, non-activating panel: clicking or dragging the countdown
/// never takes focus from the app in front (a slideshow, say).
///
/// The "meridian/window" channel mirrors windows/runner/flutter_window.cpp.
/// Rects cross it in points with a top-left origin on the primary screen,
/// and every screen reports a scale of 1, so Dart's logical pixels are
/// points.
class MainFlutterWindow: NSPanel {
  private var noActivate = false
  private var channel: FlutterMethodChannel?

  // The nib creates the window through this initialiser. A panel only
  // stays non-activating when the style is set at creation.
  override init(
    contentRect: NSRect, styleMask style: NSWindow.StyleMask,
    backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool
  ) {
    super.init(
      contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
      backing: backingStoreType, defer: flag)
  }

  override var canBecomeKey: Bool { !noActivate }
  override var canBecomeMain: Bool { !noActivate }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    self.contentViewController = flutterViewController
    self.setContentSize(NSSize(width: 420, height: 320))
    self.center()

    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    hidesOnDeactivate = false
    // Show on every desktop, including over full-screen apps.
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    RegisterGeneratedPlugins(registry: flutterViewController)

    channel = FlutterMethodChannel(
      name: "meridian/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result)
    }

    super.awakeFromNib()
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    let a = call.arguments as? [String: Any] ?? [:]
    func num(_ key: String) -> CGFloat { CGFloat((a[key] as? NSNumber)?.doubleValue ?? 0) }
    func on() -> Bool { (a["on"] as? Bool) ?? false }

    switch call.method {
    case "monitors":
      result(NSScreen.screens.map(Self.monitor))
    case "setBounds":
      // Never activates and never changes the order.
      let r = NSRect(x: num("x"), y: num("y"), width: num("w"), height: num("h"))
      setFrame(Self.flip(r), display: true)
      result(nil)
    case "bounds":
      result(Self.rectMap(Self.flip(frame)))
    case "setTopmost":
      // Above other windows but below menus. Re-asserting brings it back to
      // the front of its level without taking focus.
      level = on() ? .statusBar : .normal
      if on() && isVisible { orderFrontRegardless() }
      result(nil)
    case "setClickThrough":
      ignoresMouseEvents = on()
      result(nil)
    case "setOpacity":
      alphaValue = min(max(num("value"), 0.1), 1)
      result(nil)
    case "setNoActivate":
      noActivate = on()
      result(nil)
    case "focus":
      NSApp.activate(ignoringOtherApps: true)
      makeKeyAndOrderFront(nil)
      result(nil)
    case "startDragging":
      // Returns once the mouse is released, so Dart knows the drag is over.
      if let event = NSApp.currentEvent { performDrag(with: event) }
      result(nil)
    case "scale":
      result(backingScaleFactor)
    case "launchAtLogin":
      if #available(macOS 13.0, *) {
        result(SMAppService.mainApp.status == .enabled)
      } else {
        result(false)
      }
    case "setLaunchAtLogin":
      guard #available(macOS 13.0, *) else { return result(nil) }
      do {
        if on() {
          try SMAppService.mainApp.register()
        } else {
          try SMAppService.mainApp.unregister()
        }
        result(nil)
      } catch {
        result(FlutterError(code: "login_item", message: error.localizedDescription, details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Converts between Cocoa's bottom-left origin and a top-left one, both
  /// anchored to the primary screen. It is its own inverse.
  private static func flip(_ r: NSRect) -> NSRect {
    let height = NSScreen.screens.first?.frame.height ?? 0
    return NSRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height)
  }

  private static func rectMap(_ r: NSRect) -> [String: Int] {
    ["x": Int(r.minX.rounded()), "y": Int(r.minY.rounded()),
     "w": Int(r.width.rounded()), "h": Int(r.height.rounded())]
  }

  private static func monitor(_ screen: NSScreen) -> [String: Any] {
    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    return [
      "id": number.map { "\($0)" } ?? screen.localizedName,
      "primary": screen == NSScreen.screens.first,
      "scale": 1.0,
      "monitor": rectMap(flip(screen.frame)),
      "work": rectMap(flip(screen.visibleFrame)),
    ]
  }
}

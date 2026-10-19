import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // The window is a panel, which AppKit does not count as a window: to it
  // the app looks windowless, and closing a menu would quit it. It quits
  // from its own menu (see also MainFlutterWindow.awakeFromNib).
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

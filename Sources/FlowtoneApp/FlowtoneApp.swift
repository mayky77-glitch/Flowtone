import AppKit
import SwiftUI

@main
struct FlowtoneApp: App {
  @NSApplicationDelegateAdaptor(FlowtoneAppDelegate.self) private var appDelegate
  @StateObject private var model = FlowtoneAppModel()

  var body: some Scene {
    WindowGroup {
      FlowtoneRootView(model: model)
        .frame(minWidth: 960, minHeight: 640)
        .preferredColorScheme(.dark)
    }
    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 1_080, height: 720)
  }
}

private final class FlowtoneAppDelegate: NSObject, NSApplicationDelegate {
  func applicationWillFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.activate(ignoringOtherApps: true)
  }
}

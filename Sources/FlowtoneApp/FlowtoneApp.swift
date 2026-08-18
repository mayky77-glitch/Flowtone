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

    Settings {
      StableAudioSetupSheet(model: model)
    }
  }
}

private final class FlowtoneAppDelegate: NSObject, NSApplicationDelegate {
  private let flowtoneBundleIdentifier = "com.flowtone.app"

  func applicationWillFinishLaunching(_ notification: Notification) {
    terminateDuplicateInstances()
    NSApp.setActivationPolicy(.regular)
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.activate(ignoringOtherApps: true)
  }

  private func terminateDuplicateInstances() {
    let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    for application in NSRunningApplication.runningApplications(
      withBundleIdentifier: flowtoneBundleIdentifier
    ) where application.processIdentifier != currentProcessIdentifier {
      application.terminate()
    }
  }
}

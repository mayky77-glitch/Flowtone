import SwiftUI

@main
struct FlowtoneApp: App {
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

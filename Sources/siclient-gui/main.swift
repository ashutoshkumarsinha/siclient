import SwiftUI
import SICLientGUI

// MARK: - File Overview
// Entry point for the SICLient macOS GUI application. Creates the main window
// with ContentView and a default ClientViewModel.

/// SwiftUI app that launches the SICLient desktop interface.
@main
struct SICLientGUIApp: App {
    @State private var model = ClientViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .defaultSize(width: 960, height: 640)
    }
}

import SwiftUI
import SICLientGUI

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

import SwiftUI

@main
struct ProDisplayApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(model)
        } label: {
            Image(systemName: model.sliderValue > 1 ? "sun.max.fill" : "sun.max")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

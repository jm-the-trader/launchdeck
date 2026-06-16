import SwiftUI

@main
struct LaunchDeckApp: App {
    // One shared manager backs both the window and the menu bar item.
    @StateObject private var manager = AppManager()

    var body: some Scene {
        // `Window` (not WindowGroup) = a single unique window, so reopening it
        // from the menu bar just brings the existing one forward.
        Window("Launch Deck", id: "main") {
            ContentView(manager: manager)
        }
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Launch Deck", systemImage: "gamecontroller.fill") {
            MenuBarContent(manager: manager)
        }
    }
}

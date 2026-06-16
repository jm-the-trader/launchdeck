import SwiftUI
import AppKit

struct MenuBarContent: View {
    @ObservedObject var manager: AppManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Launch Deck — \(manager.runningCount) running")

        Divider()

        ForEach(manager.apps) { app in
            let status = manager.statuses[app.id] ?? .stopped

            Button {
                status == .stopped ? manager.start(app) : manager.stop(app)
            } label: {
                Label(actionLabel(for: app, status: status), systemImage: icon(for: status))
            }

            if status != .stopped {
                Button {
                    manager.restart(app)
                } label: {
                    Label("    Restart \(app.name)", systemImage: "arrow.clockwise")
                }
            }

            if status == .running, app.url != nil {
                Button {
                    manager.open(app)
                } label: {
                    Label("    Open \(app.name) in browser", systemImage: "arrow.up.right.square")
                }
            }
        }

        Divider()

        Button("Refresh status") { manager.refresh() }

        Button("Open Launch Deck Window") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit Launch Deck") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func actionLabel(for app: ManagedApp, status: AppStatus) -> String {
        switch status {
        case .stopped:  return "Start \(app.name)"
        case .starting: return "Stop \(app.name) (starting…)"
        case .running:  return "Stop \(app.name) (running)"
        case .stopping: return "Stop \(app.name) (stopping…)"
        }
    }

    private func icon(for status: AppStatus) -> String {
        status == .stopped ? "play.fill" : "stop.fill"
    }
}

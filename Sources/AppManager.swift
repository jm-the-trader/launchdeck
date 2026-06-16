import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppManager: ObservableObject {
    @Published private(set) var apps: [ManagedApp] = []
    @Published private(set) var statuses: [String: AppStatus] = [:]

    /// Keeps a freshly-launched app showing "Starting" until its port comes up
    /// (or this deadline passes), so polling doesn't snap it back to "Stopped".
    private var pendingUntil: [String: Date] = [:]
    /// Keeps an app showing "Stopping" while a kill is in flight, so polling
    /// doesn't flip it back to "Running" before the ports actually drain.
    private var stoppingUntil: [String: Date] = [:]
    private var timer: Timer?

    init() {
        apps = AppConfig.load()
        for app in apps { statuses[app.id] = .stopped }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop, so we're already on the main actor.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var runningCount: Int {
        statuses.values.filter { $0 == .running }.count
    }

    func refresh() {
        let apps = self.apps
        DispatchQueue.global(qos: .utility).async {
            let listening = Shell.listeningPorts()
            DispatchQueue.main.async {
                self.applyStatuses(apps: apps, listening: listening)
            }
        }
    }

    private func applyStatuses(apps: [ManagedApp], listening: Set<Int>) {
        let now = Date()
        for app in apps {
            let up = Set(app.ports).intersection(listening)

            // Mid-stop: hold "Stopping" until the ports actually drain (or a
            // safety cap passes). Without this, a poll that still sees the port
            // listening would flip the tile back to Running while the kill is
            // in flight — the Stop → Start → Stop flicker.
            if let until = stoppingUntil[app.id] {
                if !up.isEmpty && until > now {
                    statuses[app.id] = .stopping
                    continue
                }
                stoppingUntil[app.id] = nil   // drained (or capped) → resume normal logic
            }

            let status: AppStatus
            if up.isEmpty {
                if let until = pendingUntil[app.id], until > now {
                    status = .starting
                } else {
                    status = .stopped
                    pendingUntil[app.id] = nil
                }
            } else if let ready = app.effectiveReadyPort, up.contains(ready) {
                status = .running
                pendingUntil[app.id] = nil
            } else {
                status = .starting
            }
            statuses[app.id] = status
        }
    }

    func start(_ app: ManagedApp) {
        // Ignore if it's already coming up or running. Launching a second
        // ./start.sh on top of a live one leaves orphans fighting over the
        // ports, which is what makes a tile bounce back to "Stopped".
        if let s = statuses[app.id], s != .stopped { return }

        statuses[app.id] = .starting
        pendingUntil[app.id] = Date().addingTimeInterval(40)

        let command = launchCommand(for: app)
        DispatchQueue.global(qos: .userInitiated).async {
            Shell.runLogin(command)
        }
    }

    func stop(_ app: ManagedApp) {
        statuses[app.id] = .stopping
        pendingUntil[app.id] = nil
        // Hold "Stopping" until ports drain; 10s cap covers SIGTERM + SIGKILL.
        stoppingUntil[app.id] = Date().addingTimeInterval(10)

        let command = killCommand(for: app)
        DispatchQueue.global(qos: .userInitiated).async {
            Shell.runLogin(command)
        }
    }

    /// Force-stop, let the ports drain, then relaunch — all in one detached
    /// shell so the new servers reparent to launchd just like a fresh Start.
    func restart(_ app: ManagedApp) {
        statuses[app.id] = .stopping
        pendingUntil[app.id] = Date().addingTimeInterval(40)
        // Show "Stopping" only during the brief kill window; once the old ports
        // drain this clears and pendingUntil takes over (Starting → Running).
        // Kept short so it expires before the new server binds (no false stop).
        stoppingUntil[app.id] = Date().addingTimeInterval(3)

        let command = "\(killCommand(for: app)); sleep 2; \(launchCommand(for: app))"
        DispatchQueue.global(qos: .userInitiated).async {
            Shell.runLogin(command)
        }
    }

    // MARK: - Command builders

    /// Detached launch command. `nohup … &` lets the login shell exit
    /// immediately so the job reparents to launchd — quitting Launch Deck
    /// never kills your running apps.
    private func launchCommand(for app: ManagedApp) -> String {
        let dir = app.expandedDirectory.shellQuoted
        let log = AppConfig.logDir.appendingPathComponent("\(app.id).log").path.shellQuoted
        return "cd \(dir) && nohup \(app.startCommand) >> \(log) 2>&1 &"
    }

    /// Stop command. Uses a custom `stopCommand` when set; otherwise frees every
    /// port — SIGTERM first for a clean shutdown, then SIGKILL anything still
    /// holding on a second later. This is what reliably clears the port (plain
    /// SIGTERM leaves `uvicorn --reload` / vite processes lingering).
    private func killCommand(for app: ManagedApp) -> String {
        if let custom = app.stopCommand, !custom.isEmpty {
            return "cd \(app.expandedDirectory.shellQuoted) && \(custom)"
        }
        return app.ports.map { port in
            "pids=$(lsof -nP -tiTCP:\(port) -sTCP:LISTEN); " +
            "if [ -n \"$pids\" ]; then " +
            "kill $pids 2>/dev/null; sleep 1; " +
            "pids=$(lsof -nP -tiTCP:\(port) -sTCP:LISTEN); " +
            "[ -n \"$pids\" ] && kill -9 $pids 2>/dev/null; " +
            "fi"
        }.joined(separator: "; ")
    }

    func open(_ app: ManagedApp) {
        guard let raw = app.url, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }
}

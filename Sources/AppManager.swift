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

        appendLog(app, "START — \(app.startCommand)")
        let command = launchCommand(for: app)
        DispatchQueue.global(qos: .userInitiated).async {
            Shell.runLogin(command, interactive: true)   // needs ~/.zshrc for npm/node
        }
    }

    func stop(_ app: ManagedApp) {
        statuses[app.id] = .stopping
        pendingUntil[app.id] = nil
        // Hold "Stopping" until ports drain; 10s cap covers SIGTERM + SIGKILL.
        stoppingUntil[app.id] = Date().addingTimeInterval(10)

        appendLog(app, "STOP — freeing ports \(app.ports.map(String.init).joined(separator: ", "))")
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

        appendLog(app, "RESTART — \(app.startCommand)")
        let command = "\(killCommand(for: app)); sleep 2; \(launchCommand(for: app))"
        DispatchQueue.global(qos: .userInitiated).async {
            Shell.runLogin(command, interactive: true)   // needs ~/.zshrc for npm/node
        }
    }

    /// Open an app's log file in the default viewer (Console / TextEdit) so you
    /// can see what happened — including failures like "npm: command not found".
    func openLog(_ app: ManagedApp) {
        let url = logURL(for: app)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? Data().write(to: url)   // create empty so there's something to open
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Logging

    private static let logStamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func logURL(for app: ManagedApp) -> URL {
        AppConfig.logDir.appendingPathComponent("\(app.id).log")
    }

    /// Append a timestamped Launch Deck line to the app's log, so the log shows
    /// what Launch Deck *did* (the command it ran) next to the process output.
    /// The detached server appends its own stdout/stderr to the same file.
    private func appendLog(_ app: ManagedApp, _ message: String) {
        let line = "\n[\(Self.logStamp.string(from: Date()))] ▶ Launch Deck: \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let url = logURL(for: app)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)   // file didn't exist yet
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
        // Kill whatever owns each port — by *process group* (kill -<pgid>), so a
        // respawning supervisor goes down with its workers (one `kill -<pgid>`
        // takes out the whole `start.sh` tree: uvicorn reloader + worker + vite).
        // SIGTERM first for a clean shutdown, then SIGKILL anything still holding
        // on a second later.
        //
        // NOTE: piped `while read` — NOT `for pid in $pids`. These commands run
        // under /bin/zsh, which does NOT word-split unquoted parameters, so an
        // lsof result of multiple PIDs ("4990\n4993") would otherwise be passed
        // as a single bogus token and nothing gets killed (the "Stop does
        // nothing" bug). `while read` splits per line in both zsh and bash.
        let killGroup = "while read -r pid; do " +
            "pgid=$(ps -o pgid= -p \"$pid\" | tr -d ' '); " +
            "[ -n \"$pgid\" ] && kill -%@ \"-$pgid\" 2>/dev/null; done"
        return app.ports.map { port in
            let lsof = "lsof -nP -tiTCP:\(port) -sTCP:LISTEN"
            let term = killGroup.replacingOccurrences(of: "%@", with: "TERM")
            let kill = killGroup.replacingOccurrences(of: "%@", with: "KILL")
            return "\(lsof) | \(term); sleep 1; \(lsof) | \(kill)"
        }.joined(separator: "; ")
    }

    func open(_ app: ManagedApp) {
        guard let raw = app.url, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }
}

import Foundation

enum AppStatus: String, Codable {
    case stopped, starting, running
}

/// One launchable project. Decoded from apps.json so you can add apps
/// without recompiling. `id` is the name, so names must be unique.
struct ManagedApp: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
    var subtitle: String
    var icon: String            // SF Symbol name
    var color: String           // hex, e.g. "4f8cff"
    var directory: String       // working dir, supports a leading ~
    var startCommand: String    // shell command run from `directory`
    var stopCommand: String?    // optional override; default = kill the listed ports
    var ports: [Int]            // ports this app listens on (used for status + default stop)
    var readyPort: Int?         // the port that means "fully up" (usually the frontend)
    var url: String?            // opened in the browser by the Open button

    var expandedDirectory: String {
        (directory as NSString).expandingTildeInPath
    }

    /// Port that signals the app is fully ready; falls back to the last port.
    var effectiveReadyPort: Int? {
        readyPort ?? ports.last
    }
}

/// Loads/seeds apps.json under ~/Library/Application Support/LaunchDeck/.
enum AppConfig {
    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LaunchDeck", isDirectory: true)
    }
    static var configURL: URL { supportDir.appendingPathComponent("apps.json") }
    static var logDir: URL { supportDir.appendingPathComponent("logs", isDirectory: true) }

    static func load() -> [ManagedApp] {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        if let data = try? Data(contentsOf: configURL),
           let apps = try? JSONDecoder().decode([ManagedApp].self, from: data),
           !apps.isEmpty {
            return apps
        }

        // First run: write the default config so it's easy to edit later.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(defaultApps) {
            try? data.write(to: configURL)
        }
        return defaultApps
    }
}

private let githubRoot =
    "~/Library/CloudStorage/OneDrive-Personal/Desktop - onedrive/github"

let defaultApps: [ManagedApp] = [
    ManagedApp(
        name: "QuantForge",
        subtitle: "Trading platform · :5173",
        icon: "chart.line.uptrend.xyaxis",
        color: "4f8cff",
        directory: "\(githubRoot)/quantforge",
        startCommand: "./start.sh",
        stopCommand: nil,
        ports: [8000, 5173],
        readyPort: 5173,
        url: "http://localhost:5173"
    ),
    ManagedApp(
        name: "Budgeteer",
        subtitle: "Budget app · :5174",
        icon: "dollarsign.circle.fill",
        color: "34d399",
        directory: "\(githubRoot)/budgeteer",
        startCommand: "./start.sh",
        stopCommand: nil,
        ports: [8001, 5174],
        readyPort: 5174,
        url: "http://localhost:5174"
    ),
    ManagedApp(
        name: "Study App",
        subtitle: "StudyForge · :5180",
        icon: "book.fill",
        color: "f59e0b",
        directory: "\(githubRoot)/study-app",
        startCommand: "[ -d node_modules ] || npm install; npm run dev",
        stopCommand: nil,
        ports: [5180, 5182],
        readyPort: 5180,
        url: "http://localhost:5180"
    ),
]

import Foundation

extension String {
    /// Safe single-quoting for interpolation into a shell command.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum Shell {
    /// Runs a command through a login zsh (so PATH includes node/python) and
    /// returns its combined stdout/stderr. Blocking — call off the main thread.
    @discardableResult
    static func runLogin(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Every local TCP port currently in the LISTEN state.
    static func listeningPorts() -> Set<Int> {
        let out = runLogin("lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk '{print $9}'")
        var ports = Set<Int>()
        for line in out.split(separator: "\n") {
            guard let colon = line.lastIndex(of: ":") else { continue }
            let portString = line[line.index(after: colon)...]
            if let port = Int(portString) { ports.insert(port) }
        }
        return ports
    }
}

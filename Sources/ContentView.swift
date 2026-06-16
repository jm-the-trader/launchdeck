import SwiftUI

struct ContentView: View {
    @ObservedObject var manager: AppManager

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 18)]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0b0f17"), Color(hex: "11161f")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(manager.apps) { app in
                            AppTile(
                                app: app,
                                status: manager.statuses[app.id] ?? .stopped,
                                onStart: { manager.start(app) },
                                onStop: { manager.stop(app) },
                                onRestart: { manager.restart(app) },
                                onOpen: { manager.open(app) }
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "gamecontroller.fill")
                .font(.title2)
                .foregroundStyle(Color(hex: "4f8cff"))
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch Deck")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("\(manager.runningCount) running")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button { manager.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
            .help("Refresh status")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
}

struct AppTile: View {
    let app: ManagedApp
    let status: AppStatus
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void
    let onOpen: () -> Void

    private var accent: Color { Color(hex: app.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(accent.opacity(0.18))
                        .frame(width: 54, height: 54)
                    Image(systemName: app.icon)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Spacer()
                statusPill
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(app.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                if status == .stopped {
                    Button(action: onStart) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .buttonStyle(DeckButton(tint: accent, filled: true))
                } else {
                    Button(action: onStop) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .buttonStyle(DeckButton(tint: Color(hex: "f87171"), filled: false))

                    Button(action: onRestart) {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(DeckButton(tint: accent, filled: false))
                    .help("Force-stop and start again")

                    if app.url != nil {
                        Button(action: onOpen) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .buttonStyle(DeckButton(tint: accent, filled: false))
                        .disabled(status != .running)
                        .opacity(status == .running ? 1 : 0.45)
                        .help("Open in browser")
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(borderColor, lineWidth: 1.2)
                )
        )
        .shadow(color: status == .running ? accent.opacity(0.28) : .clear, radius: 14, y: 4)
        .animation(.easeInOut(duration: 0.25), value: status)
    }

    private var borderColor: Color {
        switch status {
        case .running: return accent.opacity(0.55)
        case .starting: return Color(hex: "f59e0b").opacity(0.5)
        case .stopping: return Color(hex: "f87171").opacity(0.5)
        case .stopped: return Color.white.opacity(0.08)
        }
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            switch status {
            case .running: return ("Running", Color(hex: "34d399"))
            case .starting: return ("Starting", Color(hex: "f59e0b"))
            case .stopping: return ("Stopping…", Color(hex: "f87171"))
            case .stopped: return ("Stopped", Color(hex: "94a3b8"))
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Launch Deck is a small **native macOS app** — a Steam-Deck-style control panel for
local dev projects. Each tile starts/stops/restarts a project and shows whether
it's running (by polling which TCP ports are listening). It also lives in the menu
bar. It is pure SwiftUI + AppKit with **no external dependencies and no package
manager** — it's compiled directly with `swiftc` by `build.sh` into a
double-clickable `.app` bundle.

## Commands

```bash
./build.sh            # compile Sources/*.swift into LaunchDeck.app (needs Xcode CLT)
open LaunchDeck.app   # run it
cp -R LaunchDeck.app /Applications/   # install (then drag to Dock to keep it)

./make_icon.sh        # re-render AppIcon.icns from Icon/make_icon.swift (optional)
```

There is no test suite, linter, or CI. Verification = `./build.sh` compiles
cleanly. After changing any `Sources/*.swift`, run `./build.sh` to confirm it
builds; `swiftc` errors are the only build feedback. A running instance keeps the
*old* binary — quit it (menu bar → Quit Launch Deck) and `open LaunchDeck.app`
again to test changes.

Requires macOS 13+ (target is set in `build.sh`).

## Architecture

`@main` is in `Sources/LaunchDeckApp.swift`. It builds one shared `AppManager`
and presents two scenes that share it: a single `Window` (the grid) and a
`MenuBarExtra` (the menu). All source lives in `Sources/`:

- **`LaunchDeckApp.swift`** — app entry; wires the shared `AppManager` into the
  window and the menu-bar item.
- **`AppManager.swift`** — the core. `@MainActor ObservableObject` that owns the
  app list and per-app `statuses`, polls status every 2.5s, and runs
  start/stop/restart. **All process control lives here.**
- **`Models.swift`** — `ManagedApp` (one project, `Codable`), `AppStatus`
  (`stopped` / `starting` / `running`), and `AppConfig` (loads/seeds the JSON
  config). Also holds `defaultApps`, the seed list.
- **`Shell.swift`** — `Shell.runLogin(_:)` runs a command through a login `zsh`
  (`zsh -lc`, so PATH includes node/python); `Shell.listeningPorts()` parses
  `lsof` for the set of LISTENing TCP ports. `String.shellQuoted` safely
  single-quotes interpolated values.
- **`ContentView.swift`** — the grid window UI: header + `AppTile`s with
  Start / Stop / Restart / Open buttons.
- **`MenuBarContent.swift`** — the menu-bar menu (same actions, plus Refresh /
  Open Window / Quit).
- **`Theme.swift`** — `Color(hex:)` and the `DeckButton` button style.
- **`Icon/make_icon.swift`** — draws the app icon (run via `make_icon.sh`).

### How process control works (important before touching AppManager)

- **Config** lives at `~/Library/Application Support/LaunchDeck/apps.json`
  (NOT in this repo). On first run `AppConfig.load()` seeds it from `defaultApps`
  in `Models.swift`. To change which apps ship by default, edit `defaultApps`;
  to change a user's live apps, they edit that JSON. Per-app logs go to
  `~/Library/Application Support/LaunchDeck/logs/<App>.log`.
- **Start** runs the app's `startCommand` from its `directory`, detached via
  `cd … && nohup <cmd> >> <log> 2>&1 &`. The login shell exits immediately so the
  servers reparent to `launchd` — quitting Launch Deck never kills running apps.
  `start()` ignores the request if the app isn't `stopped`, so you can't stack
  duplicate launches fighting over the same ports.
- **Status** is inferred purely from listening ports (`Shell.listeningPorts()`),
  polled every 2.5s. An app is `running` once its `effectiveReadyPort`
  (`readyPort`, else the last port) is up, `starting` while only some ports are
  up or within the 40s `pendingUntil` grace window after a launch, else
  `stopped`. There is no PID tracking — the ports ARE the source of truth.
- **Stop / Restart** free the ports via `killCommand`: SIGTERM first for a clean
  shutdown, then SIGKILL anything still holding the port a second later. Plain
  SIGTERM alone leaves `uvicorn --reload` / vite processes lingering, which is
  why the escalation matters. A `ManagedApp.stopCommand`, if set, overrides this.
  **Restart** = `killCommand; sleep 2; launchCommand` in one detached shell.

## Conventions

- Match the existing Swift style: small focused files, `@MainActor` on
  `AppManager`, comments that explain *why* (especially around the detach /
  port-polling / kill-escalation behavior).
- No third-party dependencies — keep it `swiftc`-buildable with just SwiftUI +
  AppKit. Don't introduce SwiftPM/CocoaPods.
- Any shell command built from user/config values must go through
  `String.shellQuoted`.
- The committed `AppIcon.icns` is a build asset; its source is
  `Icon/make_icon.swift`. The compiled `LaunchDeck.app/` is git-ignored.

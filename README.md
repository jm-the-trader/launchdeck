# Launch Deck

A small native macOS app — a Steam-Deck-style control panel for your local dev
projects. Each tile starts/stops a project and shows whether it's running.

Ships configured for **QuantForge**, **Budgeteer**, and **Study App**.

## Build & run

```bash
cd LaunchDeck
./build.sh          # compiles LaunchDeck.app with swiftc (needs Xcode CLT)
open LaunchDeck.app # launch it
```

To keep it in your Dock: `cp -R LaunchDeck.app /Applications/` and drag it from
there onto the Dock.

## How it works

- **Start** runs the app's `startCommand` from its directory, detached via
  `nohup … &`. Because the launching shell exits immediately, the servers are
  reparented to `launchd` — so quitting Launch Deck never kills your apps.
- **Status** is detected by polling which TCP ports are in `LISTEN` (every
  2.5s). An app is *Running* once its `readyPort` (the frontend) is up,
  *Starting* while only some ports are up.
- **Stop** sends `SIGTERM` to whatever owns the app's ports (or runs a custom
  `stopCommand` if you set one).
- **Open** opens the app's `url` in your browser.

Per-app logs are written to
`~/Library/Application Support/LaunchDeck/logs/<App>.log`.

## Adding or editing apps

Config lives in:

```
~/Library/Application Support/LaunchDeck/apps.json
```

It's seeded on first run. Edit it and relaunch (or hit refresh). Each entry:

```json
{
  "name": "My App",
  "subtitle": "Anything · :3000",
  "icon": "bolt.fill",                  // any SF Symbol name
  "color": "4f8cff",                    // hex, no #
  "directory": "~/code/my-app",
  "startCommand": "npm run dev",
  "stopCommand": null,                  // null = kill the ports below
  "ports": [3000, 4000],                // used for status + default stop
  "readyPort": 3000,                    // the port that means "fully up"
  "url": "http://localhost:3000"        // Open button (or null)
}
```

The defaults baked into the binary are in `Sources/Models.swift`.

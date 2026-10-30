# Contributing to NotchCurtain

Thank you for your interest in contributing. This guide covers how to set up your environment, build from source, run tests, and submit changes.

## Guiding Principles

1. **Native & Restrained:** Adhere strictly to Apple Human Interface Guidelines and native macOS aesthetics. No unnecessary UI chrome, intrusive notifications, or heavy animations.
2. **Zero Telemetry:** The app must remain 100% offline and local by default. Never introduce network telemetry, remote tracking, or third-party analytics libraries.
3. **Battery & CPU Efficiency:** Avoid unmeasured CPU claims. Keep polling adaptive and avoid unnecessary disk scans or process launches.
4. **Reliability:** UI updates must stay on the `@MainActor`. All blocking pipe reads, child process launches, and IPC communication must remain in detached actors or background tasks.

## Prerequisites

- macOS 14.0 (Sonoma) or newer.
- MacBook with a physical display notch (MacBook Pro 14"/16" 2021+, MacBook Air 13"/15" M2+).
- Xcode 15+ or Command Line Tools (`xcode-select --install`).
- Swift 5.9+.
- CMake (required to build the media remote helper):
  ```bash
  brew install cmake
  ```

## Development Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/kaTrek0406/NotchCurtain.git
   cd NotchCurtain
   ```

2. **Run the test suite:**
   ```bash
   swift test
   ```

3. **Build the application bundle:**
   ```bash
   ./scripts/build_app.sh
   ```
   The script builds the Swift release binary, fetches and compiles the pinned `mediaremote-adapter` framework via CMake, packages `.build/NotchCurtain.app`, and signs it ad-hoc.

4. **Launch the local build:**
   ```bash
   ./scripts/install.sh
   ```

## Project Structure

```
├── Sources/
│   └── NotchCurtain/
│       ├── AppMain.swift               # Application entry point & lifecycle
│       ├── AppBrand.swift              # Branding, bundle ID & settings store
│       ├── NotchPanelController.swift  # Floating NSPanel pinned to hardware notch
│       ├── NotchGeometry.swift         # Physical display notch calculation
│       ├── NotchRootView.swift         # Main SwiftUI curtain container & tabs
│       ├── ExternalSessionScanner.swift# Local CLI agent scanner (ps/lsof/jsonl)
│       ├── MusicProvider.swift         # Now Playing adapter IPC bridge
│       ├── RateLimits.swift            # Local rate limit readers (Codex/Orca)
│       ├── SettingsView.swift          # User preferences panel
│       └── [en|ru].lproj/              # English & Russian localization
├── Tests/
│   └── NotchCurtainTests/                    # Unit tests & parsing fixtures
└── scripts/
    ├── build_app.sh                    # Bundle packager & ad-hoc code sign
    ├── fetch_adapter.sh                # Fetches & builds mediaremote-adapter
    └── install.sh                      # Quick build & launch script
```

## Pull Request Guidelines

- Keep pull requests focused on a single feature, bug fix, or documentation update.
- Ensure all unit tests pass (`swift test`).
- Test your changes on physical hardware with a display notch.
- Do not check in build artifacts, `.DS_Store`, personal paths, or confidential fixture data.
- If introducing user-facing text, provide strings in both `en.lproj` and `ru.lproj`.

## Screenshot Demo Mode

Use `--demo` or `NC_DEMO=1` to run with fabricated data for screenshots. The demo presents five sample agent sessions, Claude limits of 41%/14%, Codex limits of 22%/9%, and a generated neutral cover for “Demo Track” by “Demo Artist”; it does not show Orca cards. In this mode the app does not poll Orca, scan processes or session files, or start the Now Playing adapter. For example:

```sh
NC_DEMO=1 NOTCH_CURTAIN_SETTINGS_PATH=/tmp/notch-curtain-demo-settings.json .build/NotchCurtain.app/Contents/MacOS/NotchCurtain
```

The custom settings path keeps demo preference changes separate from the normal user settings. Do not capture the desktop or unrelated windows when preparing screenshots; capture only the app window or render its view.

# NTE Fishing Bot Mac

Unofficial macOS fishing helper for the native macOS client of NTE.

This project provides:

- a Swift command-line fishing automation core
- a native SwiftUI control app
- pixel-based fishing bar detection
- normal macOS keyboard/mouse event input only

It does not modify game files, memory, or network traffic.

## Status

This is a macOS-only project focused on fishing automation. It is not a full
MaaNTE port and does not include auto sell, auto buy bait, or Windows support.

Current tested flow:

- start from the fishing-ready scene
- press the visible `F` prompt to start fishing
- wait for the blue hook prompt
- control the fishing bar with `A` / `D`
- close result screen
- loop until stopped or the configured catch count is reached

## Requirements

- macOS 14 or later
- Xcode or Xcode Command Line Tools
- Screen Recording permission
- Accessibility permission

Permissions are required for the app or terminal process that runs the bot:

- `System Settings -> Privacy & Security -> Screen Recording`
- `System Settings -> Privacy & Security -> Accessibility`

## Recommended Use

Most users should use the SwiftUI app built by:

```bash
script/build_app.sh
open dist/MacFishingBotControl.app
```

Grant Screen Recording and Accessibility permissions to
`MacFishingBotControl.app`, then quit and reopen it once.

Recommended game setup:

- native macOS NTE client
- windowed or borderless-windowed mode
- stable window size
- balanced preset in the app: `0,33 1280x804`

## Build

Build the command-line tool:

```bash
script/build_cli.sh
```

Build the SwiftUI app:

```bash
script/build_app.sh
```

Create local release zip files:

```bash
script/package_release.sh
```

Build artifacts are written to `dist/`, which is intentionally ignored by git.

By default the app is ad-hoc signed. To sign with your own certificate:

```bash
MAC_FISHING_BOT_SIGN_IDENTITY="Developer ID Application: Your Name" script/build_app.sh
```

## CLI Examples

List visible windows:

```bash
cd cli
swift run mac-fishing-bot list --all NTE
```

Check capture size:

```bash
cd cli
swift run mac-fishing-bot size --match 異環
```

Probe fishing detection without input:

```bash
cd cli
swift run mac-fishing-bot fish-probe sample-fish-config.json
```

Run live:

```bash
cd cli
swift run mac-fishing-bot fish-run sample-fish-config.json --live
```

## Safety

- Use the app's Stop or Pause button to stop automation.
- Emergency stop shortcut in the app: `Command + Option + .`
- In CLI mode, press `Control + C`.
- If the game window loses focus in frontmost input mode, the bot releases held
  keys and waits until the game is frontmost again.

## Repository Layout

```text
cli/      Swift command-line bot core
app/      SwiftUI control app source
script/   build and packaging scripts
docs/     usage and troubleshooting notes
dist/     local build output, ignored by git
```

## What Is Not Included

This clean public version intentionally excludes:

- local debug screenshots
- user screen recordings
- generated app bundles and binaries
- previous development outputs
- Windows MaaNTE inspection files
- local workspace metadata

Release binaries should be uploaded separately through GitHub Releases.

## License

AGPL-3.0-or-later. See `LICENSE`.

## Disclaimer

This project is unofficial and not affiliated with the game developer,
publisher, MaaNTE, or MaaAssistantArknights. Use at your own risk.

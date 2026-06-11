# NTE Fishing Bot Mac

<p align="center">
  <strong>Unofficial macOS fishing automation for the native NTE client.</strong>
</p>

<p align="center">
  <a href="README.zh-TW.md">繁體中文</a>
  ·
  <a href="docs/TROUBLESHOOTING.md">Troubleshooting</a>
  ·
  <a href="CONTRIBUTING.md">Contributing</a>
  ·
  <a href="CHANGELOG.md">Changelog</a>
  ·
  <a href="docs/PUBLISHING.md">Publishing</a>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-111111">
  <img alt="Language" src="https://img.shields.io/badge/language-Swift-orange">
  <img alt="License" src="https://img.shields.io/badge/license-AGPL--3.0--or--later-blue">
  <img alt="Status" src="https://img.shields.io/badge/status-fishing%20focused-green">
</p>

## Overview

NTE Fishing Bot Mac is a small native macOS helper focused on one workflow:
repeatable fishing in the native macOS client of NTE.

It provides:

- a SwiftUI control app for normal users
- a Swift command-line tool for testing and tuning
- pixel-based detection for fishing prompts, the hook prompt, the fishing bar,
  and the result screen
- normal macOS keyboard and mouse events only

It does not modify game files, memory, network traffic, or the game process.

## Current Scope

This project is not a full MaaNTE port. The current public version focuses on
stable fishing automation only.

| Supported | Not included |
| --- | --- |
| Start fishing from the ready fishing scene | Auto sell fish |
| Wait for the blue hook prompt | Auto buy bait |
| Control the bar with `A` / `D` | Multi-task Maa workflow |
| Close the result screen | Windows support |
| Loop until stopped or target count is reached | PlayCover support |

## Requirements

| Item | Requirement |
| --- | --- |
| Operating system | macOS 14 or later |
| Game client | Native macOS NTE client |
| CPU | Apple Silicon build is provided by default |
| Permissions | Screen Recording and Accessibility |
| Recommended window | Windowed or borderless-windowed |
| Tested size | `0,33 1280x804` |

Required macOS permissions:

- `System Settings -> Privacy & Security -> Screen Recording`
- `System Settings -> Privacy & Security -> Accessibility`

After granting permissions, quit and reopen the app once.

## Quick Start

### Option 1: Download the app

1. Download `MacFishingBotControl-macOS-arm64.zip` from GitHub Releases.
2. Unzip it.
3. Open `MacFishingBotControl.app`.
4. Grant Screen Recording and Accessibility permissions if macOS asks.
5. Restart the app after changing permissions.
6. Open NTE and switch to a stable windowed size.
7. Select the NTE window in the app.
8. Press `Start`.

### Option 2: Build locally

```bash
git clone https://github.com/Louis-369/NTEFishingBotMac.git
cd NTEFishingBotMac
script/build_app.sh
open dist/MacFishingBotControl.app
```

To create release archives locally:

```bash
script/package_release.sh
```

The generated files are written to `dist/`.

## Recommended Game Setup

Use a stable windowed or borderless-windowed game window. The currently tested
balanced preset is:

```text
x=0 y=33 width=1280 height=804
```

The app includes a fixed-size helper so users do not need to edit the JSON
configuration manually.

The bot works best when:

- the game window size is stable
- the right-side action icons are visible
- the bottom-right `F` fishing prompt is not blocked
- the fishing bar appears near the top-center of the window
- macOS display scaling is not changed during a run

## How It Works

The automation loop is state-based:

1. Detect the fishing-ready scene.
2. Press `F` to start fishing.
3. Wait until the blue hook prompt appears.
4. Press `F` again to enter the fishing bar.
5. Detect the green target range and the yellow cursor.
6. Hold or switch `A` / `D` to keep the cursor inside the green range.
7. Detect the result screen.
8. Click the result prompt area to close it.
9. Repeat until stopped or the configured catch count is reached.

The default control mode is `holdSwitch`, tuned for the current macOS native
client and the balanced `1280x804` window preset.

## App Controls

| Control | Purpose |
| --- | --- |
| Start | Begin the fishing loop |
| Pause | Temporarily pause automation |
| Stop | Stop automation and release held keys |
| Window picker | Select the target NTE window |
| Fixed size | Apply the tested window size |
| Detection panel | Show green/cursor/offset/current key |
| Log panel | Show the current bot decisions |
| Advanced settings | Tune detection and timing parameters |

Emergency stop in the app:

```text
Command + Option + .
```

CLI emergency stop:

```text
Control + C
```

## CLI Usage

Build the command-line tool:

```bash
script/build_cli.sh
```

Run a self-test:

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot self-test
```

List visible windows:

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot list --all NTE
```

Check capture size:

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot size --match NTE
```

Probe fishing detection without sending input:

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot fish-probe cli/sample-fish-config.json
```

Run fishing automation:

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot fish-run cli/sample-fish-config.json --live
```

## Configuration Notes

The main sample config is `cli/sample-fish-config.json`.

Important defaults:

| Key | Default | Meaning |
| --- | --- | --- |
| `dryRun` | `false` | App default sends real input |
| `inputMode` | `global` | Use normal macOS frontmost input |
| `pauseWhenTargetNotFrontmost` | `true` | Release keys if the game is not frontmost |
| `loopIntervalMs` | `16` | Main fishing scan interval |
| `controlMode` | `holdSwitch` | Hold one direction and switch when needed |
| `deadzonePx` | `15` | Ignore tiny bar offsets |
| `assistRequiresPrompt` | `true` | Only assist when prompt detection is visible |

Most users should tune these from the app instead of editing JSON directly.

## Repository Layout

```text
app/      SwiftUI control app source
cli/      Swift command-line bot core and sample configs
docs/     publishing and troubleshooting notes
script/   build and packaging scripts
dist/     local build output, ignored by git
```

## Project References

This project was developed after studying the automation approach and public
documentation style of the following open-source projects:

- [MaaNTE](https://github.com/1bananachicken/MaaNTE)
- [MaaNTE documentation](https://docs.maante.org/)
- [MaaAssistantArknights](https://github.com/MaaAssistantArknights/MaaAssistantArknights)

Those projects are references and inspirations only. NTE Fishing Bot Mac is an
independent macOS-only implementation and does not claim compatibility with the
Maa framework task system.

## Privacy and Safety

The tool reads pixels from the selected window and sends normal macOS input
events. It does not patch the game, inject code, inspect memory, or proxy
network traffic.

Automation may violate a game's terms of service. Use at your own risk.

## License

AGPL-3.0-or-later. See `LICENSE`.

## Disclaimer

This project is unofficial and is not affiliated with, endorsed by, or supported
by the NTE developer or publisher, MaaNTE, or MaaAssistantArknights.

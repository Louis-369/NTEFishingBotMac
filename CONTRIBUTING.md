# Contributing

Thanks for helping improve NTE Fishing Bot Mac.

This project is intentionally narrow: the first priority is stable fishing on
the native macOS client. Please keep changes focused and verifiable.

## Before Opening an Issue

Check:

- macOS Screen Recording permission is enabled.
- macOS Accessibility permission is enabled.
- The game is running in a stable window size.
- The selected window in the app is the actual NTE game window.
- You are using the latest release or latest `main` branch.

## Bug Report Checklist

For fishing failures, include:

- macOS version
- Mac model and chip
- game window size shown in the app
- whether the app or CLI was used
- control mode and key tuning values if changed
- the last 30-60 log lines around the failure
- a short screen recording from before the failure to after the failure

Useful log patterns:

```text
start prompt visible kind=ready; pressing f
hook prompt visible; pressing f
bar offset=... green=... cursor=... hold=...
result prompt visible; closing...
```

## Development

Build the CLI:

```bash
script/build_cli.sh
```

Run the CLI self-test:

```bash
dist/mac-fishing-bot/bin/mac-fishing-bot self-test
```

Build the app:

```bash
script/build_app.sh
```

Create local release zips:

```bash
script/package_release.sh
```

## Pull Requests

Keep pull requests small. A good PR should explain:

- what state or detection problem it changes
- why the change is needed
- which window size and game state were tested
- whether it changes default settings
- which commands were used to verify the change

Do not commit:

- `dist/`
- `.build/`
- local screenshots
- screen recordings
- personal configs
- generated binaries

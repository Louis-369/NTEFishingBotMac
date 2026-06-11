# Troubleshooting

## The App Cannot See the Game Window

1. Open the game first.
2. Press Refresh in the app window picker.
3. Try matching `NTE` instead of `異環`.
4. If the game is in a macOS full-screen Space, switch to windowed or
   borderless-windowed mode for setup.

## Screen Is Black or Detection Fails

Grant Screen Recording permission to the exact app or terminal process that is
running the bot. After changing permission, quit and reopen the app.

## Keys Go to the Wrong App

Use the default global/frontmost input mode with the game frontmost. If you
switch away, the bot releases held keys and waits for the game to become
frontmost again.

The experimental PID input mode may work for some actions, but some games ignore
process-targeted events. If it behaves strangely, return to global/frontmost
mode.

## Fishing Gets Stuck on the Ready Scene

The bot detects the bottom-right action icons and presses `F`. If it does not,
open the log and check for:

```text
start prompt visible kind=ready; pressing f
```

If the line appears but the game does not move, the key event was likely eaten by
the game transition. If the line does not appear, the prompt detection region or
colors need recalibration for your window size.

## Fishing Bar Is Unstable

Keep the game window size stable. The tested balanced size is:

```text
0,33 1280x804
```

When reporting an issue, include the log lines around the failure:

```text
bar offset=... control=... green=... zone=... hold=...
```

Also include a short screen recording from the start of the fishing bar until
the failure.


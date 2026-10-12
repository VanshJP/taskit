# Taskit

A macOS menu bar app that queues prompts for **Claude Code** and runs them one after another, waiting out usage limits for you.

Queue up the day's work, press Start, and walk away. Taskit sends each prompt to Claude Code in your project folder. When one finishes, it sends the next. When your plan's usage limit hits ("You've hit your session limit · resets 3:45pm"), it waits until the reset and carries on.

## How it works

Each prompt runs as a headless Claude Code call in the folder you choose:

```
claude --output-format json [--resume <session>] [--permission-mode auto] -p "<prompt>"
```

- **One thread** (default): every prompt resumes the previous prompt's session, so Claude keeps the context from earlier steps.
- **Fresh each time**: every prompt starts a new session.
- **Usage limits**: Taskit reads the reset time from Claude Code's message, waits until then (plus a minute), and retries the same prompt in the same session. If no time is given, it retries after 30 minutes.
- **Failures**: a failed prompt is marked and the queue moves on. Taskit pauses instead if Claude Code isn't signed in, can't be found, or three prompts fail in a row.
- **Quitting mid-run**: the interrupted prompt goes back in the queue and runs again next launch.

Taskit uses your own `claude` login (Pro or Max plan). It removes `ANTHROPIC_API_KEY` from the environment it passes to Claude Code, so runs use your subscription rather than API billing.

## Using it

- **Add prompts**: type in the box at the bottom and press Enter. To add several at once, paste a list: put each prompt on its own line, or separate longer prompts with a blank line.
- **Reorder or remove**: hover a queued prompt and use the arrow and ✕ buttons. Right-click a prompt for more options.
- **Pause** (header button): the current prompt finishes, then nothing new starts. To cancel the current prompt immediately, use the stop button on its row; the prompt goes back in the queue.
- **See what Claude did**: click a finished prompt to show its reply. From there, **Open in Terminal** resumes that session interactively, and **Run again** puts the prompt back in the queue.

The menu bar shows what's happening at a glance: prompts queued (`3`), progress (`2/5`), time left until the limit resets (`2:14`), or `Paused`.

## Requirements

- macOS 14 or later
- [Claude Code](https://code.claude.com/docs/en/setup), installed and signed in
- Xcode 15 or later (Swift 5.9) to build

## Build and run

```bash
./scripts/build-macos-app.sh
open dist/Taskit.app
```

For development, you can also run it straight from the package with `cd Taskit && swift run Taskit`. Notifications and Open at login only work in the packaged `.app`.

On first launch, the panel walks you through setup: it finds `claude`, can check that you're signed in, and asks you to pick a project folder.

## Keeping it running overnight

Taskit keeps the Mac awake while prompts are running or waiting on a limit (Settings → Keep the Mac awake). It can't stop sleep when the lid is closed, so keep the lid open or the Mac on power with the display off. Turn on **Open at login** so a queue survives a restart.

## Tests

```bash
cd Taskit
swift test
```

The queue logic lives in `TaskitCore`, which only needs Foundation, so the tests also build on Linux. They cover limit and reset-time parsing, Claude output parsing, the queue engine (ordering, pause and stop, limits, failures, relaunch), persistence, and the process runner. CI runs the build, tests, and app packaging on macOS for every pull request.

## Files

- Queue and settings: `~/Library/Application Support/Taskit/` (`queue.json`, `settings.json`). If a file can't be read, it's renamed to `*.corrupt` rather than overwritten.
- Taskit makes no network calls itself. Claude Code does the talking to Anthropic.

## License

MIT

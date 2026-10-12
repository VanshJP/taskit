# Taskit

A native macOS menu bar app for asynchronous Cursor goal relays.

Queue the prompts you want for the day. When a session finishes — or when a five-hour limit window clears — Taskit sends the next one through the [Cursor Cloud Agents API](https://cursor.com/docs/cloud-agent/api/overview), even if you are away from the laptop.

## Why

Cursor is excellent for goal-based agent work, but usage windows and finished sessions still need a human to come back and re-prompt. Taskit turns that into a queue:

1. Set an overarching day goal
2. Stack ordered prompts
3. Start the relay
4. Walk away — overnight, meetings, whatever
5. When the cool-down ends (default **5 hours**, configurable), Taskit fires the next prompt automatically

## Features

- **Menu bar panel** with liquid-glass UI (vibrancy, soft seafoam accent, serif timer)
- **Day goal + prompt queue** with reorder, edit, skip, requeue, and clear
- **Bulk paste** a whole day plan (blank lines → separate prompts)
- **Pause / resume** auto-relay without losing the queue
- **Copy composed prompt** for desktop Cursor when you want a clipboard handoff
- **Setup checklist** when API key or queue is missing; **Test** API key in Settings
- **Session clock** for limit cool-downs (1h / 2h / 5h / 8h / default, or auto-detect `429`)
- **Auto-resume** when the window clears (unless paused)
- **Auto-continue** when a Cloud Agent run finishes (unless paused)
- **Continue one agent** (follow-up runs) or **new agent per goal**
- **Keychain** storage for your Cursor API key
- **Notifications** for dispatch, completion, and limit events
- **Launch at login** (signed `.app` builds)

## Requirements

- macOS 14+
- Xcode 15+ / Swift 5.9+
- A Cursor API key from [Dashboard → API Keys](https://cursor.com/dashboard?tab=integrations)
- A connected repository (optional for no-repo agents)

## Build & run

```bash
cd Taskit
swift build
swift run Taskit
```

Or package a menu-bar `.app`:

```bash
chmod +x scripts/build-macos-app.sh
./scripts/build-macos-app.sh
open dist/Taskit.app
```

First launch: open **Settings** from the panel, paste your API key, set the repo URL / branch, then queue prompts and hit **Start relay**.

## How the relay works

```
Day goal ──► Prompt 1 ──► (running) ──► finished
                              │
                         limit hit? ──► cool-down clock ──► Prompt 2
                              │
                              └── auto-continue ──────────► Prompt 2
```

Each dispatch prepends your overarching goal (unless disabled) so follow-ups stay aligned.

## Design preview

Open `design-preview/index.html` in a browser for a static mock of the menu bar panel (useful when you are not on a Mac).

Visual references used while designing: [Tiimo focus](https://mobbin.com/screens/ffeedfca-2932-4798-9f5a-fccdaff4f095), [Oura session](https://mobbin.com/screens/08366dca-8bef-401f-a5d2-2514448fdf7d), [Todoist inbox](https://mobbin.com/screens/da55b0b7-581f-4b7c-90ea-5e1e57da7c21).

## Tests

```bash
cd Taskit
swift test
```

Covers limit-text parsing and session clock transitions.

## Privacy

- API keys live in the macOS Keychain (`app.taskit.menubar`)
- Goals / settings persist under `~/Library/Application Support/Taskit/`
- Network calls go only to `https://api.cursor.com`

## Note on “five-hour” windows

Cursor’s included usage is primarily monthly. Short rate-limit / cool-down messages still show up in practice, and many people plan overnight work around a ~5 hour gate. Taskit treats that as a **configurable session window**: mark it manually, or let the engine parse reset hints / HTTP 429 from the Cloud Agents API.

## License

MIT

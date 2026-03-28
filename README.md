# SuperSamuel

SuperSamuel is a personal macOS dictation app inspired by Superwhisper:

- Global `Option+Space` to start/stop recording
- Center overlay with live waveform, timer, and recent transcript lines
- Minimal floating overlay built with AppKit + SwiftUI
- Real-time transcription via SinusoidLabs `spark`
- Auto-paste into the active text field (with clipboard fallback)

## Project Layout

- `app/` - native macOS app (Swift + AppKit/SwiftUI)
- `broker/` - older local token broker prototype; not required for the current app flow

## Requirements

- macOS 13+
- Xcode Command Line Tools

Install them if needed:

```bash
xcode-select --install
```

## Quick Start

1. Clone the repo and enter it:

   ```bash
   git clone https://github.com/marclelamy/SuperSamuel.git
   cd SuperSamuel
   ```

2. Save your SinusoidLabs API key:

   ```bash
   mkdir -p ~/.supersamuel
   printf '%s\n' 'sk-slabs-...' > ~/.supersamuel/api_key
   ```

   You can also use an environment variable instead:

   ```bash
   export SUPERSAMUEL_API_KEY='sk-slabs-...'
   ```

3. Build, install, sign, and launch the app from the repo root:

   ```bash
   ./rebuild-app.sh
   ```

   This rebuilds the Swift app, refreshes `~/Applications/SuperSamuel.app`, quits any
   running copy, and launches the new build.

4. Grant macOS permissions on first launch:

   - Microphone
   - Accessibility

5. Use `Option+Space` to start and stop dictation.

## Development Run

If you just want to run the executable directly during development:

```bash
cd app
swift run
```

That does not replace the installed app in `~/Applications`. To rebuild the installed app,
run `./rebuild-app.sh` from the repo root.

## API Key Loading

The app looks for credentials in this order:

1. `~/.supersamuel/api_key`
2. `SUPERSAMUEL_API_KEY`

## Required macOS Permissions

- Microphone access
- Accessibility access (for global hotkey capture and text insertion/paste)

If Accessibility permission is missing, use the menu bar action `Open Accessibility Settings`.

## Notes

- Tokens are fetched directly from SinusoidLabs in the current app flow; the local broker is not needed.
- Menu bar options include toggles for:
  - Auto Paste Result
  - Restore Clipboard


Le truc de l'espace, il marche trop bien. Genre, en vrai, franchement, genre, il marche de ouf. Et aussi, parfois, il y a des petits bugs, parce que genre, si t'as pas le... si par exemple la tuile, t'as rien de focus,
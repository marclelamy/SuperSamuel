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
   #!/usr/bin/env bash
   set -euo pipefail

   REPO_ROOT="$(pwd)"
   APP_DIR="$REPO_ROOT/app"
   APP_NAME="SuperSamuel"

   SRC_APP="$APP_DIR/$APP_NAME.app"
   BUILD_BIN="$APP_DIR/.build/debug/$APP_NAME"
   INSTALLED_APP="$HOME/Applications/$APP_NAME.app"

   mkdir -p "$HOME/Applications"

   cd "$APP_DIR"
   swift build

   cp -f "$BUILD_BIN" "$SRC_APP/Contents/MacOS/$APP_NAME"

   codesign --force --deep --sign - \
     --identifier com.supersamuel.app \
     -r='designated => identifier "com.supersamuel.app"' \
     "$SRC_APP"

   rm -rf "$INSTALLED_APP"
   ditto "$SRC_APP" "$INSTALLED_APP"

   open "$INSTALLED_APP"
   ```

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
- Default final tail wait: `1800ms`
- Menu bar options include toggles for:
  - Auto Paste Result
  - Restore Clipboard

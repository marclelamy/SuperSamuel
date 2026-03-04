# SuperSamuel

SuperSamuel is a personal macOS dictation app inspired by Superwhisper:

- Global `Option+Space` to start/stop recording
- Center overlay with live waveform, timer, and recent transcript lines
- Liquid-glass style panel using AppKit material/vibrancy
- Real-time transcription via SinusoidLabs `spark`
- Auto-paste into the active text field (with clipboard fallback)

## Project Layout

- `broker/` - local token broker (TypeScript, pnpm)
- `app/` - native macOS app (Swift + AppKit/SwiftUI)
- `.env` - root secret file (`API_KEY=...`)

## Security Model

The app does **not** keep your long-lived SinusoidLabs API key.  
The local broker reads `API_KEY` from `.env`, exchanges it for short-lived tokens, and only returns temporary tokens to the app.

## Setup

1. Ensure `.env` exists at repo root:

   ```bash
   API_KEY="sk-slabs-..."
   ```

2. Install broker dependencies:

   ```bash
   pnpm --dir broker install
   ```

3. Start token broker:

   ```bash
   pnpm --dir broker dev
   ```

4. In a second terminal, run the macOS app:

   ```bash
   cd app
   swift run
   ```

## Required macOS Permissions

- Microphone access
- Accessibility access (for global hotkey capture and text insertion/paste)

If Accessibility permission is missing, use the menu bar action:

- `Open Accessibility Settings`

When running with `swift run` during development, macOS may attribute automation permission prompts to the built binary path and/or Terminal. If paste automation is blocked, ensure both the app process and your terminal app are allowed under Accessibility.

## Notes

- Default broker endpoint: `http://127.0.0.1:8787/token`
- Default final tail wait: `1800ms` before finalizing transcript
- Menu bar options include toggles for:
  - Auto Paste Result
  - Restore Clipboard

## Handoff (Current Status)

### What Works

- The broker starts and returns temporary Sinusoid tokens.
- The app starts and shows `SS` in the menu bar.
- `Option+Space` starts and stops recording.
- Live waveform and live transcript preview work.
- The 3-line rolling transcript preview is working.

### How We Usually Get Good Results

1. Start broker first: `pnpm --dir broker dev`
2. Start app second: `cd app && swift run`
3. Click the target text field before recording.
4. Record with `Option+Space`, then stop with `Option+Space`.

### Known Bug (Short, Calm Explanation)

Sometimes, after stopping recording, the app enters `SS INS` and does not paste or copy text.
Recording/transcription can still work, but the insert step may fail.
This looks like a focus/timing issue during the handoff from the overlay back to the target app.

### Temporary Workarounds

- Quit and relaunch the app if it stays in `SS INS`.
- Turn off `Auto Paste Result` and use `Copy Last Transcript`, then paste manually.
- Re-focus the target text field and try one more recording cycle.

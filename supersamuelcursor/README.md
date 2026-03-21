# SuperSamuelCursor

Cursor extension that can:

- copy the current Cursor conversation to the clipboard
- record voice on macOS through `ffmpeg`
- stream audio live to SinusoidLabs
- rewrite the transcript with OpenRouter using the active Cursor conversation as optional context
- copy the final result to the clipboard

## Current UX

- status bar voice control with phase-specific states
- red recording indicator with elapsed time while capturing
- post-stop wait animation while the transcript is finalized and rewritten
- existing `Copy Current Cursor Conversation` command still available

## API Keys

The extension stores secrets in Cursor/VS Code `SecretStorage`.

Saved keys:

- `superSamuel.sinusoidApiKey`
- `superSamuel.openRouterApiKey`

Fallback environment variables:

- `SUPERSAMUEL_SINUSOID_API_KEY`
- `SUPERSAMUEL_API_KEY`
- `OPENROUTER_API_KEY`

Useful commands:

- `SuperSamuelCursor: Set SinusoidLabs API Key`
- `SuperSamuelCursor: Set OpenRouter API Key`
- `SuperSamuelCursor: Clear Saved API Keys`

## Requirements

- macOS for voice recording
- `sqlite3` installed
- `ffmpeg` installed
- Cursor or another VS Code-compatible extension host

## Voice Flow

1. Start voice capture from the status bar or with `Shift+Option+Space` on macOS
2. The extension streams microphone audio live to SinusoidLabs
3. When you stop, the extension waits for the best available final transcript
4. The extension loads the active Cursor conversation from local Cursor storage
5. OpenRouter rewrites the raw transcript using that context
6. The final text is copied to the clipboard

## Settings

Non-secret settings live in normal extension settings:

- `superSamuelCursor.ffmpegPath`
- `superSamuelCursor.sinusoidModel`
- `superSamuelCursor.openRouterModel`
- `superSamuelCursor.openRouterTemperature`
- `superSamuelCursor.openRouterBaseUrl`
- `superSamuelCursor.rewriteInstruction`
- `superSamuelCursor.contextMaxChars`
- `superSamuelCursor.finalizationTailMs` (advanced)

`contextMaxChars` rules:

- `-1` or unset: send all active conversation context
- `0`: send no conversation context
- positive number: send the last `N` characters of the active conversation markdown

## Local Development

1. Open `cursor-chat-copy/` as its own project in Cursor
2. Press `F5` and run the `Run SuperSamuelCursor` launch config
3. In the Extension Development Host window, open a real workspace
4. Use the status bar voice control or the command palette
5. Run `npm run check`
6. If Cursor cannot find `ffmpeg` automatically, set `superSamuelCursor.ffmpegPath`

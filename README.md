# SuperSamuel

SuperSamuel is a small native macOS dictation app:

- Press `Option+Space` to start and stop recording.
- Record locally as 16 kHz mono WAV audio.
- Finalize recordings into small, durable chunks.
- Transcribe once through OpenRouter with `openai/whisper-large-v3`.
- Optionally clean the transcript with any OpenRouter model or preset.
- Paste the result back into the app that was active while dictating.
- Optionally attach a screenshot as context for a vision-capable cleanup model.

There is no realtime websocket, token broker, or streaming transcript path.

On macOS 26 and newer, the compact notification-style recording overlay and
settings window use untinted native **clear Liquid Glass** across their full
surface, with clear-glass controls. A subtle moving chromatic backdrop gives
the untinted glass light to refract even above nearly black applications.
SuperSamuel does not add a custom blur layer. Older macOS versions use a
non-blurred, translucent fallback because native Liquid Glass is unavailable
there.

## Requirements

- macOS 13 or newer
- Xcode Command Line Tools
- An OpenRouter API key with available credits

Install the command-line tools if needed:

```bash
xcode-select --install
```

## Build and install

From the repository root:

```bash
./rebuild-app.sh
```

The script builds, signs, installs, and opens `~/Applications/SuperSamuel.app`.
It uses an optimized release build by default. For a faster local rebuild:

```bash
BUILD_CONFIGURATION=debug ./rebuild-app.sh
```

For a development-only build:

```bash
cd app
swift build
```

## Configure OpenRouter

1. Open the `SS` menu-bar item.
2. Choose **Settings…**
3. Enter your OpenRouter API key. It is stored in the macOS Keychain.
4. Enter a cleanup model or preset.

Examples:

```text
openai/gpt-5.4-nano
@preset/my-dictation-cleanup
```

The transcription model is fixed to:

```text
openai/whisper-large-v3
```

OpenRouter presets can control model selection, fallbacks, provider routing,
system prompts, and generation parameters. SuperSamuel does not send a
request-level temperature for cleanup, so a preset's temperature is preserved.

## Permissions

SuperSamuel may request:

- **Microphone** — required to record dictation.
- **Accessibility** — required for automatic paste. Without it, the result is
  still copied to the clipboard.
- **Screen Recording** — required only when attaching screenshot context.

## Request flow

```text
record durable WAV chunks
  → OpenRouter Whisper Large V3 transcription
  → optional OpenRouter cleanup
  → clipboard
  → optional Command+V paste
```

The recording file and any attached screenshot are temporary and are removed
only after the final transcript has been saved successfully.

During recording, the waveform is calculated from the converted samples after
they have been written successfully, rather than directly from the microphone
input. SuperSamuel continuously checks write progress and stops with a
recoverable error if microphone input is present but the saved output is
silent or stalled. Each completed WAV chunk is reopened and verified for
readable frames, duration, RMS, and peak level before transcription.

## Recording recovery

Audio is stored under:

```text
~/Library/Application Support/SuperSamuel/Recordings/
```

Each recording has its own folder containing:

- WAV chunks finalized at a pause after two minutes, or after five minutes maximum
- A JSON manifest
- Cached raw and cleaned transcript parts
- The final transcript while processing completes
- Optional screenshot context

If transcription, cleanup, cancellation, or app shutdown interrupts processing,
the recording remains in this folder. On the next launch, SuperSamuel presents
the oldest unsent recording and offers:

- **Send Recording**
- **Keep for Later**
- **Move to Trash**

The menu-bar **Unsent Recordings** submenu also supports sending, revealing the
folder in Finder, or moving it to Trash after confirmation. The recording
manifest includes the selected input device, route changes, and per-chunk
signal measurements. New recordings remain blocked while unsent recordings
exist.

If transcription returns empty text for a chunk whose saved WAV contains a
verified signal, SuperSamuel retries once and keeps the audio retryable instead
of permanently marking it as silence.

Successfully processed text is stored under:

```text
~/Library/Application Support/SuperSamuel/Transcript History/
```

The **Transcript History** submenu shows recent transcript previews. Selecting
one copies its full text. History remains until explicitly cleared.

## Upload limits

OpenRouter's speech-to-text multipart endpoint currently limits each direct file
upload to **25 MB**. Its separate Files API has a **100 MB** limit, but that is
not the endpoint used for transcription.

SuperSamuel records 16 kHz mono, 16-bit WAV and rotates at the first short pause
after two minutes, with a five-minute hard maximum. Each request is therefore
normally about 4–10 MB, regardless of the total recording length. Completed
chunk transcripts are cached, so retrying after a later failure does not
retranscribe successful chunks. Silence-only chunks are marked and skipped, so
an extended pause cannot block the spoken parts that follow it.

Groq's direct API documents **25 MB on the free tier** and **100 MB on the
developer tier**, while direct attachment uploads are still capped at 25 MB.
Those Groq account limits do not replace OpenRouter's own request limit when
calling through OpenRouter.

Official references:

- [OpenRouter speech-to-text](https://openrouter.ai/docs/guides/overview/multimodal/stt)
- [OpenRouter transcription API](https://openrouter.ai/docs/api/api-reference/stt/create-transcription)
- [OpenRouter presets](https://openrouter.ai/docs/guides/features/presets)
- [Groq speech-to-text](https://console.groq.com/docs/speech-to-text)

## Manual verification

- Start and stop recording with `Option+Space`.
- Confirm the waveform and timer update while recording.
- Cancel during transcription and confirm nothing is pasted.
- Confirm the cancelled recording appears under **Unsent Recordings**.
- Relaunch with an unsent recording and test Send, Keep, Reveal, and Delete.
- Test cleanup with a normal model ID and with `@preset/...`.
- Test cleanup enabled and disabled.
- Test automatic paste in Notes, a browser textarea, and a code editor.
- Test clipboard restoration.
- Test screenshot cleanup and fallback when the selected model cannot read images.
- Quit during recording and confirm the saved recording appears after relaunch.
- Confirm completed transcripts appear in **Transcript History**.

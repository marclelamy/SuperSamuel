'use strict';

const path = require('path');
const vscode = require('vscode');
const { findWorkspaceForFolder, getGlobalDbPath } = require('./lib/paths');
const { loadCurrentConversation } = require('./lib/cursorConversation');
const { formatConversationMarkdown } = require('./lib/format');
const { VoicePhase, VoiceStateStore } = require('./lib/state');
const {
    clearSavedApiKeys,
    getOpenRouterApiKey,
    getSinusoidApiKey,
    setOpenRouterApiKey,
    setSinusoidApiKey
} = require('./lib/secrets');
const { rewriteTranscript } = require('./lib/openrouter');
const { startFfmpegStreaming } = require('./lib/ffmpegRecorder');
const { createRealtimeTranscriptionSession } = require('./lib/sinusoid');
const {
    appendTimestampedLine,
    formatNumberWithSeparators,
    formatRelativeElapsedMs
} = require('./lib/logging');

let outputChannel;
let voiceState;
let statusBarItem;
let currentVoiceRun = null;
let idleResetTimer = null;
let voiceRunCounter = 0;
let lastLoggedSnapshotSignature = '';
let waitAnimationTimer = null;
let waitAnimationState = null;
let waitAnimationSnapshot = null;

const BRAND_NAME = 'SuperSamuelCursor';
const CONFIG_NAMESPACE = 'superSamuelCursor';
const LEGACY_CONFIG_NAMESPACE = 'cursorChatCopy';
const DEFAULT_SINUSOID_MODEL = 'spark';
const DEFAULT_FINALIZATION_TAIL_MS = 1800;
const DEFAULT_OPENROUTER_MODEL = 'qwen/qwen3-32b';
const DEFAULT_OPENROUTER_BASE_URL = 'https://openrouter.ai/api/v1/chat/completions';
const DEFAULT_OPENROUTER_TEMPERATURE = 0;
const DEFAULT_CONTEXT_MAX_CHARS = -1;
const DEFAULT_FFMPEG_AUDIO_INPUT = ':0';
const DEFAULT_REWRITE_INSTRUCTION =
    'Rewrite the raw transcript into clean written dictation while preserving all meaning and technical details. Remove filler words such as um, uh, like when used as filler, you know, repeated words, false starts, self-corrections, stutters, and speech artifacts. Keep the same intent, facts, uncertainty, and level of detail. Do not summarize, shorten for brevity, add new facts, or pull in content from the chat context except to fix an obviously misrecognized technical term, code symbol, product name, or proper noun. Return only the cleaned transcript.';
const RECORDING_TEXT_COLOR = '#f44747';
const DONE_TEXT_COLOR = '#4ec9b0';
const WAIT_ANIMATION_INTERVAL_MS = 90;
const WAIT_ANIMATION_WIDTH = 6;
const WAIT_BALL_CHAR = '●';
const WAIT_TRACK_CHAR = '·';
const WAIT_TEXT_COLORS = Object.freeze([
    '#f44747',
    '#ce9178',
    '#dcdcaa',
    '#4ec9b0',
    '#569cd6',
    '#c586c0',
    '#ff79c6',
    '#ffd700'
]);
const WAIT_BACKGROUND_OPTIONS = Object.freeze([
    undefined,
    new vscode.ThemeColor('statusBarItem.warningBackground'),
    new vscode.ThemeColor('statusBarItem.errorBackground')
]);

async function copyCurrentConversation() {
    try {
        const conversation = loadCurrentConversationForActiveWorkspace();

        const clipboardText = formatConversationMarkdown(conversation);
        await vscode.env.clipboard.writeText(clipboardText);

        const title = conversation.title || 'Untitled conversation';
        const message = `Copied "${title}" (${conversation.messages.length} messages) to the clipboard.`;
        vscode.window.setStatusBarMessage(message, 4000);
        await vscode.window.showInformationMessage(message);
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        vscode.window.showErrorMessage(`${BRAND_NAME}: ${message}`);
    }
}

function hasConfiguredValue(inspectedValue) {
    return Boolean(
        inspectedValue &&
            (inspectedValue.workspaceFolderValue !== undefined ||
                inspectedValue.workspaceValue !== undefined ||
                inspectedValue.globalValue !== undefined)
    );
}

function getConfigValue(config, legacyConfig, key, defaultValue, legacyKey = key) {
    const inspectedValue = config.inspect(key);
    if (hasConfiguredValue(inspectedValue)) {
        return config.get(key, defaultValue);
    }

    const legacyInspectedValue = legacyConfig.inspect(legacyKey);
    if (hasConfiguredValue(legacyInspectedValue)) {
        return legacyConfig.get(legacyKey, defaultValue);
    }

    return config.get(key, defaultValue);
}

function normalizeFinalizationTailMs(value) {
    const numericValue = Number(value);
    if (!Number.isFinite(numericValue)) {
        return DEFAULT_FINALIZATION_TAIL_MS;
    }

    return Math.max(300, Math.floor(numericValue));
}

function normalizeOpenRouterTemperature(value) {
    const numericValue = Number(value);
    if (!Number.isFinite(numericValue)) {
        return DEFAULT_OPENROUTER_TEMPERATURE;
    }

    return Math.max(0, Math.min(2, numericValue));
}

function normalizeContextMaxChars(value) {
    const numericValue = Number(value);
    if (!Number.isFinite(numericValue)) {
        return DEFAULT_CONTEXT_MAX_CHARS;
    }

    if (numericValue === 0) {
        return 0;
    }

    if (numericValue < 0) {
        return -1;
    }

    return Math.max(1, Math.floor(numericValue));
}

function getStartStopShortcutLabel() {
    return process.platform === 'darwin' ? 'Shift+Option+Space' : 'Ctrl+Alt+Shift+R';
}

function getIdleDetail() {
    return `Press ${getStartStopShortcutLabel()} or click the Voice button in the status bar to start recording.`;
}

function getSettings() {
    const config = vscode.workspace.getConfiguration(CONFIG_NAMESPACE);
    const legacyConfig = vscode.workspace.getConfiguration(LEGACY_CONFIG_NAMESPACE);

    return {
        ffmpegPath: getConfigValue(config, legacyConfig, 'ffmpegPath', ''),
        sinusoidModel: getConfigValue(
            config,
            legacyConfig,
            'sinusoidModel',
            DEFAULT_SINUSOID_MODEL
        ),
        finalizationTailMs: normalizeFinalizationTailMs(
            getConfigValue(
                config,
                legacyConfig,
                'finalizationTailMs',
                DEFAULT_FINALIZATION_TAIL_MS
            )
        ),
        openRouterModel: getConfigValue(
            config,
            legacyConfig,
            'openRouterModel',
            DEFAULT_OPENROUTER_MODEL
        ),
        openRouterTemperature: normalizeOpenRouterTemperature(
            getConfigValue(
                config,
                legacyConfig,
                'openRouterTemperature',
                DEFAULT_OPENROUTER_TEMPERATURE
            )
        ),
        openRouterBaseUrl: getConfigValue(
            config,
            legacyConfig,
            'openRouterBaseUrl',
            DEFAULT_OPENROUTER_BASE_URL
        ),
        rewriteInstruction: getConfigValue(
            config,
            legacyConfig,
            'rewriteInstruction',
            DEFAULT_REWRITE_INSTRUCTION,
            'cleanupInstruction'
        ),
        contextMaxChars: normalizeContextMaxChars(
            getConfigValue(
                config,
                legacyConfig,
                'contextMaxChars',
                DEFAULT_CONTEXT_MAX_CHARS
            )
        )
    };
}

function formatElapsed(elapsedMs) {
    const totalSeconds = Math.max(0, Math.floor(elapsedMs / 1000));
    const minutes = String(Math.floor(totalSeconds / 60)).padStart(2, '0');
    const seconds = String(totalSeconds % 60).padStart(2, '0');
    return `${minutes}:${seconds}`;
}

function createAbortError(message = 'Voice capture canceled.') {
    const error = new Error(message);
    error.name = 'AbortError';
    return error;
}

function isAbortError(error) {
    return error instanceof Error && error.name === 'AbortError';
}

function logLine(message, timestampMs = Date.now()) {
    appendTimestampedLine(outputChannel, '', message, timestampMs);
}

function logExtension(message) {
    logLine(`[extension] ${message}`);
}

function logRun(run, message, timestampMs = Date.now()) {
    const relativeElapsed = run?.startedAt
        ? ` +${formatRelativeElapsedMs(timestampMs - run.startedAt)}`
        : '';
    logLine(`${run?.logPrefix || '[voice]'}${relativeElapsed} ${message}`, timestampMs);
}

function logSection(run, title) {
    outputChannel?.appendLine('');
    logRun(run, `========== ${title} ==========`);
}

function buildConversationContext(conversation, contextMaxChars) {
    const fullMarkdown = formatConversationMarkdown(conversation);

    if (contextMaxChars === 0) {
        return {
            fullMarkdown,
            contextMarkdown: '',
            contextMaxChars,
            wasTrimmed: fullMarkdown.length > 0
        };
    }

    if (contextMaxChars < 0) {
        return {
            fullMarkdown,
            contextMarkdown: fullMarkdown,
            contextMaxChars,
            wasTrimmed: false
        };
    }

    return {
        fullMarkdown,
        contextMarkdown: fullMarkdown.slice(-contextMaxChars),
        contextMaxChars,
        wasTrimmed: fullMarkdown.length > contextMaxChars
    };
}

function handleRealtimeSnapshot(run, snapshot) {
    if (currentVoiceRun !== run) {
        return;
    }

    run.lastRealtimeSnapshot = snapshot;
}

function formatError(error) {
    if (error instanceof Error) {
        const firstStackLine = String(error.stack || '')
            .split('\n')
            .slice(1, 3)
            .map((line) => line.trim())
            .join(' | ');
        return firstStackLine ? `${error.message} :: ${firstStackLine}` : error.message;
    }

    return String(error);
}

function beginTimedStep() {
    return Date.now();
}

function recordStepMetric(run, stepName, durationMs, detail = '', status = 'done') {
    if (!run) {
        return;
    }

    if (!run.stepMetrics) {
        run.stepMetrics = new Map();
    }

    if (!run.stepOrder) {
        run.stepOrder = [];
    }

    if (!run.stepMetrics.has(stepName)) {
        run.stepOrder.push(stepName);
    }

    run.stepMetrics.set(stepName, {
        durationMs,
        detail,
        status
    });
}

function endTimedStep(run, stepName, startedAt, detail = '') {
    const endedAt = Date.now();
    const durationMs = endedAt - startedAt;
    const suffix = detail ? ` ${detail}` : '';
    recordStepMetric(run, stepName, durationMs, detail, 'done');
    logRun(
        run,
        `[timing] ${stepName} done duration=${formatNumberWithSeparators(durationMs)} ms${suffix}`,
        endedAt
    );
    return durationMs;
}

function failTimedStep(run, stepName, startedAt, error) {
    const failedAt = Date.now();
    const durationMs = failedAt - startedAt;
    recordStepMetric(run, stepName, durationMs, formatError(error), 'failed');
    logRun(
        run,
        `[timing] ${stepName} failed duration=${formatNumberWithSeparators(durationMs)} ms error=${formatError(error)}`,
        failedAt
    );
}

async function measureTimedStep(run, stepName, detail, operation, successDetail) {
    const startedAt = beginTimedStep();
    try {
        const result = await operation();
        const resolvedSuccessDetail =
            typeof successDetail === 'function' ? successDetail(result) : successDetail;
        endTimedStep(run, stepName, startedAt, resolvedSuccessDetail);
        return result;
    } catch (error) {
        failTimedStep(run, stepName, startedAt, error);
        throw error;
    }
}

function logContextSubstep(run, step, durationMs, detail = '') {
    recordStepMetric(run, `context.${step}`, durationMs, detail, 'done');
    const suffix = detail ? ` ${detail}` : '';
    logRun(
        run,
        `[timing] context.${step} duration=${formatNumberWithSeparators(durationMs)} ms${suffix}`
    );
}

function updateRunMetrics(run, updates) {
    if (!run || !updates) {
        return;
    }

    run.metrics = {
        ...(run.metrics || {}),
        ...updates
    };
}

function logRunSummary(run) {
    if (!run) {
        return;
    }

    const metrics = run.metrics || {};
    outputChannel?.appendLine('');
    logRun(run, '----- SUMMARY -----');
    logRun(
        run,
        `[summary] transcriptChars=${formatNumberWithSeparators(metrics.rawChars)} finalChars=${formatNumberWithSeparators(metrics.finalChars)} contextChars=${formatNumberWithSeparators(metrics.contextChars)} fullContextChars=${formatNumberWithSeparators(metrics.fullContextChars)} contextMessages=${formatNumberWithSeparators(metrics.contextMessages)}`
    );

    const stepOrder = run.stepOrder || [];
    for (const stepName of stepOrder) {
        const metric = run.stepMetrics?.get(stepName);
        if (!metric) {
            continue;
        }

        const detail = metric.detail ? ` ${metric.detail}` : '';
        const status = metric.status && metric.status !== 'done' ? ` status=${metric.status}` : '';
        logRun(
            run,
            `[summary] ${stepName}=${formatNumberWithSeparators(metric.durationMs)} ms${status}${detail}`
        );
    }

    outputChannel?.appendLine('');
}

function markRunCanceled(run, reason) {
    if (!run) {
        return;
    }

    if (!run.canceled) {
        run.canceled = true;
        run.cancelReason = reason;
        logRun(run, `marked canceled (${reason})`);
        return;
    }

    if (!run.cancelReason) {
        run.cancelReason = reason;
    }
}

function ensureRunActive(run) {
    if (!run || run.canceled || run.abortController.signal.aborted || currentVoiceRun !== run) {
        const reason =
            run?.cancelReason ||
            (run?.abortController.signal.aborted
                ? 'Abort signal set.'
                : currentVoiceRun !== run
                  ? `Current run changed to ${currentVoiceRun?.id ?? 'none'}.`
                  : 'Run object missing.');
        throw createAbortError(reason);
    }
}

function clearIdleResetTimer() {
    if (idleResetTimer) {
        clearTimeout(idleResetTimer);
        idleResetTimer = null;
    }
}

function scheduleReturnToIdle() {
    clearIdleResetTimer();
    idleResetTimer = setTimeout(() => {
        voiceState.transition(VoicePhase.IDLE, {
            title: 'Ready',
            detail: getIdleDetail()
        });
    }, 2500);
}

function clearWaitAnimation() {
    if (waitAnimationTimer) {
        clearInterval(waitAnimationTimer);
        waitAnimationTimer = null;
    }

    waitAnimationState = null;
    waitAnimationSnapshot = null;
}

function pickRandomValue(values) {
    return values[Math.floor(Math.random() * values.length)];
}

function pickNextWaitAppearance() {
    return {
        textColor: pickRandomValue(WAIT_TEXT_COLORS),
        backgroundColor: pickRandomValue(WAIT_BACKGROUND_OPTIONS)
    };
}

function createWaitAnimationState() {
    return {
        position: 0,
        direction: 1,
        ...pickNextWaitAppearance()
    };
}

function isWaitingForFinalVoiceResult(snapshot = voiceState?.getSnapshot()) {
    return Boolean(
        snapshot &&
            currentVoiceRun?.stopRequestedAt &&
            (snapshot.phase === VoicePhase.TRANSCRIBING || snapshot.phase === VoicePhase.CLEANUP)
    );
}

function buildWaitAnimationText(position) {
    const track = Array.from({ length: WAIT_ANIMATION_WIDTH + 1 }, () => WAIT_TRACK_CHAR);
    track[position] = WAIT_BALL_CHAR;
    return track.join('');
}

function renderWaitAnimation() {
    if (!statusBarItem || !waitAnimationState) {
        return;
    }

    const snapshot = waitAnimationSnapshot || voiceState?.getSnapshot();
    statusBarItem.text = buildWaitAnimationText(waitAnimationState.position);
    statusBarItem.tooltip = snapshot
        ? `${snapshot.title}: ${snapshot.detail}`
        : 'Waiting for the voice result...';
    statusBarItem.command = undefined;
    statusBarItem.color = waitAnimationState.textColor;
    statusBarItem.backgroundColor = waitAnimationState.backgroundColor;
    statusBarItem.show();
}

function advanceWaitAnimation() {
    if (!waitAnimationState) {
        return;
    }

    const nextPosition = waitAnimationState.position + waitAnimationState.direction;
    if (nextPosition >= WAIT_ANIMATION_WIDTH) {
        waitAnimationState.position = WAIT_ANIMATION_WIDTH;
        waitAnimationState.direction = -1;
        Object.assign(waitAnimationState, pickNextWaitAppearance());
        return;
    }

    if (nextPosition <= 0) {
        waitAnimationState.position = 0;
        waitAnimationState.direction = 1;
        Object.assign(waitAnimationState, pickNextWaitAppearance());
        return;
    }

    waitAnimationState.position = nextPosition;
}

function ensureWaitAnimation(snapshot) {
    waitAnimationSnapshot = snapshot;
    if (!waitAnimationState) {
        waitAnimationState = createWaitAnimationState();
        renderWaitAnimation();
    }

    if (waitAnimationTimer) {
        return;
    }

    waitAnimationTimer = setInterval(() => {
        advanceWaitAnimation();
        renderWaitAnimation();
    }, WAIT_ANIMATION_INTERVAL_MS);
}

function updateStatusBar(snapshot = voiceState?.getSnapshot()) {
    if (!statusBarItem || !snapshot) {
        return;
    }

    if (isWaitingForFinalVoiceResult(snapshot)) {
        ensureWaitAnimation(snapshot);
        return;
    }

    clearWaitAnimation();
    statusBarItem.backgroundColor = undefined;
    statusBarItem.color = undefined;

    if (snapshot.phase === VoicePhase.RECORDING) {
        statusBarItem.text = `● REC ${formatElapsed(snapshot.elapsedMs)}`;
        statusBarItem.tooltip = `Press ${getStartStopShortcutLabel()} or click to stop recording.`;
        statusBarItem.command = 'cursorChatCopy.stopVoiceCapture';
        statusBarItem.color = RECORDING_TEXT_COLOR;
    } else if (snapshot.phase === VoicePhase.TRANSCRIBING) {
        statusBarItem.text = '$(sync~spin) Starting Voice';
        statusBarItem.tooltip = snapshot.detail;
        statusBarItem.command = undefined;
    } else if (snapshot.phase === VoicePhase.CLEANUP) {
        statusBarItem.text = '$(sync~spin) Rewriting Voice';
        statusBarItem.tooltip = `${snapshot.title}: ${snapshot.detail}`;
        statusBarItem.command = undefined;
    } else if (snapshot.phase === VoicePhase.DONE) {
        statusBarItem.text = '✓ done';
        statusBarItem.tooltip = 'Voice capture finished. Click to copy the final text again.';
        statusBarItem.command = 'cursorChatCopy.showVoiceDone';
        statusBarItem.color = DONE_TEXT_COLOR;
    } else if (snapshot.phase === VoicePhase.ERROR) {
        statusBarItem.text = '✕ error';
        statusBarItem.tooltip = snapshot.errorMessage || 'Voice capture failed. Click for details.';
        statusBarItem.command = 'cursorChatCopy.showVoiceError';
        statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
    } else {
        statusBarItem.text = '$(mic) Voice';
        statusBarItem.tooltip = `Start voice capture (${getStartStopShortcutLabel()}).`;
        statusBarItem.command = 'cursorChatCopy.startVoiceCapture';
    }

    statusBarItem.show();
}

function loadCurrentConversationForActiveWorkspace(options = {}) {
    const { onTiming } = options;
    const workspaceFolders = vscode.workspace.workspaceFolders;
    if (!workspaceFolders || workspaceFolders.length === 0) {
        throw new Error('Open a workspace folder in Cursor first.');
    }

    const workspaceFolderPath = workspaceFolders[0].uri.fsPath;
    const activeTabLabel = vscode.window.tabGroups.activeTabGroup?.activeTab?.label ?? '';

    const workspaceLookupStartedAt = Date.now();
    const workspaceMatch = findWorkspaceForFolder(workspaceFolderPath);
    onTiming?.({
        step: 'workspace.lookup',
        durationMs: Date.now() - workspaceLookupStartedAt,
        detail: workspaceMatch
            ? `hash=${workspaceMatch.hash} name=${workspaceMatch.name}`
            : 'match=(none)'
    });
    if (!workspaceMatch) {
        throw new Error(
            `Could not locate Cursor workspace storage for "${path.basename(workspaceFolderPath)}".`
        );
    }

    const globalDbPath = getGlobalDbPath();
    const conversation = loadCurrentConversation({
        workspaceDbPath: workspaceMatch.dbPath,
        globalDbPath,
        activeTabLabel,
        workspaceFolderPath,
        onTiming
    });

    return {
        ...conversation,
        activeTabLabel
    };
}

async function handleRecordingCompletion(context, run) {
    let recordingResult = null;
    try {
        recordingResult = await measureTimedStep(
            run,
            'ffmpeg.stop_wait',
            'waiting for ffmpeg recording to finish',
            () => run.recordingSession.completion,
            (result) => `streamedBytes=${result.byteLength}`
        );
        ensureRunActive(run);

        voiceState.transition(VoicePhase.TRANSCRIBING, {
            title: 'Transcribing',
            detail: 'Finalizing the live SinusoidLabs transcript...'
        });
        const settings = getSettings();
        logRun(
            run,
            `finalizing live Sinusoid transcription model=${settings.sinusoidModel} tailMs=${settings.finalizationTailMs}`
        );
        const rawTranscript = await measureTimedStep(
            run,
            'sinusoid.finalize',
            `tailMs=${settings.finalizationTailMs}`,
            () =>
                run.sttSession.finishAndWait({
                    finalizationTailMs: settings.finalizationTailMs,
                    signal: run.abortController.signal
                }),
            (result) => `chars=${result.length}`
        );
        ensureRunActive(run);
        updateRunMetrics(run, { rawChars: rawTranscript.length });

        voiceState.transition(VoicePhase.CLEANUP, {
            title: 'Rewriting transcript',
            detail: 'Rewriting the transcript against the current Cursor conversation.',
            rawTranscript,
            finalText: '',
            errorMessage: ''
        });

        const conversation = await measureTimedStep(
            run,
            'context.load',
            'loading current Cursor conversation',
            () =>
                Promise.resolve(
                    loadCurrentConversationForActiveWorkspace({
                        onTiming: ({ step, durationMs, detail }) =>
                            logContextSubstep(run, step, durationMs, detail)
                    })
                ),
            (result) => `title="${result.title}" messages=${result.messages.length}`
        );
        const conversationContext = await measureTimedStep(
            run,
            'context.prepare',
            `contextMaxChars=${settings.contextMaxChars}`,
            () =>
                Promise.resolve(
                    buildConversationContext(conversation, settings.contextMaxChars)
                ),
            (result) =>
                `fullChars=${result.fullMarkdown.length} contextChars=${result.contextMarkdown.length} trimmed=${result.wasTrimmed ? 'yes' : 'no'}`
        );
        updateRunMetrics(run, {
            contextMessages: conversation.messages.length,
            fullContextChars: conversationContext.fullMarkdown.length,
            contextChars: conversationContext.contextMarkdown.length
        });
        const openRouterApiKey = await measureTimedStep(
            run,
            'openrouter.key',
            'loading OpenRouter API key',
            () => getOpenRouterApiKey(context),
            'ready'
        );
        const finalText = await measureTimedStep(
            run,
            'openrouter.rewrite',
            `model=${settings.openRouterModel} contextChars=${conversationContext.contextMarkdown.length}`,
            () =>
                rewriteTranscript({
                    apiKey: openRouterApiKey,
                    baseUrl: settings.openRouterBaseUrl,
                    model: settings.openRouterModel,
                    temperature: settings.openRouterTemperature,
                    contextMarkdown: conversationContext.contextMarkdown,
                    rawTranscript,
                    rewriteInstruction: settings.rewriteInstruction,
                    signal: run.abortController.signal,
                    outputChannel,
                    logPrefix: run.logPrefix
                }),
            (result) => `chars=${result.length}`
        );
        ensureRunActive(run);
        updateRunMetrics(run, { finalChars: finalText.length });

        await measureTimedStep(
            run,
            'clipboard.write',
            `chars=${finalText.length}`,
            () => vscode.env.clipboard.writeText(finalText),
            'copied'
        );
        voiceState.transition(VoicePhase.DONE, {
            title: 'Done',
            detail: 'Final text copied to the clipboard.',
            rawTranscript,
            finalText,
            errorMessage: ''
        });
        vscode.window.setStatusBarMessage('Voice text copied to the clipboard.', 4000);
        scheduleReturnToIdle();
        void vscode.window.showInformationMessage('Done. Final text copied to the clipboard.');
    } catch (error) {
        if (run.canceled || isAbortError(error)) {
            logRun(run, `capture canceled (${run.cancelReason || formatError(error)})`);
            return;
        }

        const message = error instanceof Error ? error.message : String(error);
        logRun(run, `pipeline failed: ${formatError(error)}`);
        voiceState.transition(VoicePhase.ERROR, {
            title: 'Voice capture failed',
            detail: 'Check the message below and try again.',
            errorMessage: message
        });
        scheduleReturnToIdle();
        void vscode.window.showErrorMessage(`${BRAND_NAME}: ${message}`);
    } finally {
        const finishedAt = Date.now();
        recordStepMetric(run, 'run.total', finishedAt - run.startedAt);
        if (run.stopRequestedAt) {
            recordStepMetric(run, 'run.post_stop', finishedAt - run.stopRequestedAt);
        }
        logRunSummary(run);
        run.sttSession?.cancel('completion cleanup');
        recordingResult?.cleanup?.();
        if (currentVoiceRun === run) {
            currentVoiceRun = null;
        }
        logSection(run, 'RUN END');
    }
}

async function startVoiceCapture(context) {
    if (currentVoiceRun) {
        await vscode.window.showInformationMessage('Voice capture is already running.');
        return;
    }

    try {
        clearIdleResetTimer();
        clearWaitAnimation();
        const settings = getSettings();
        const runId = ++voiceRunCounter;
        const run = {
            id: runId,
            logPrefix: `[run#${runId}]`,
            abortController: new AbortController(),
            canceled: false,
            cancelReason: '',
            startedAt: Date.now(),
            stepMetrics: new Map(),
            stepOrder: [],
            metrics: {},
            sttSession: null,
            recordingSession: null
        };

        logSection(run, 'RUN START');
        logRun(
            run,
            `starting capture ffmpegPath=${settings.ffmpegPath || '(auto)'} audioInput=${DEFAULT_FFMPEG_AUDIO_INPUT} sinusoidModel=${settings.sinusoidModel} openRouterModel=${settings.openRouterModel} temperature=${settings.openRouterTemperature} contextMaxChars=${settings.contextMaxChars}`
        );
        const sinusoidApiKey = await measureTimedStep(
            run,
            'sinusoid.key',
            'loading SinusoidLabs API key',
            () => getSinusoidApiKey(context),
            'ready'
        );
        currentVoiceRun = run;
        voiceState.transition(VoicePhase.TRANSCRIBING, {
            title: 'Starting microphone',
            detail: 'Connecting to SinusoidLabs and preparing live transcription...'
        });

        run.sttSession = createRealtimeTranscriptionSession({
            apiKey: sinusoidApiKey,
            model: settings.sinusoidModel,
            outputChannel,
            logPrefix: run.logPrefix,
            onSnapshot: (snapshot) => handleRealtimeSnapshot(run, snapshot)
        });
        await measureTimedStep(
            run,
            'sinusoid.start',
            `model=${settings.sinusoidModel}`,
            () => run.sttSession.start({ signal: run.abortController.signal }),
            'ready for live audio'
        );

        const ffmpegStartAt = Date.now();
        run.recordingSession = startFfmpegStreaming({
            ffmpegPath: settings.ffmpegPath,
            outputChannel,
            logPrefix: run.logPrefix,
            onChunk: (chunk) => run.sttSession.sendAudioChunk(chunk)
        });
        endTimedStep(run, 'ffmpeg.start', ffmpegStartAt, 'streaming live audio');
        voiceState.transition(VoicePhase.RECORDING, {
            title: 'Recording',
            detail: `Speak now. Press ${getStartStopShortcutLabel()} or click the Voice button in the status bar to stop.`,
            rawTranscript: '',
            finalText: '',
            errorMessage: ''
        });
        void handleRecordingCompletion(context, run);
        void vscode.window.showInformationMessage(
            `Recording started. Press ${getStartStopShortcutLabel()} or click the Voice button in the status bar to stop.`
        );
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        logExtension(`startVoiceCapture failed: ${formatError(error)}`);
        currentVoiceRun?.sttSession?.cancel('start failure');
        currentVoiceRun?.recordingSession?.cancel();
        currentVoiceRun = null;
        voiceState.transition(VoicePhase.ERROR, {
            title: 'Voice capture failed',
            detail: 'The recording workflow could not start.',
            errorMessage: message
        });
        await vscode.window.showErrorMessage(`${BRAND_NAME}: ${message}`);
        scheduleReturnToIdle();
    }
}

async function stopVoiceCapture() {
    if (!currentVoiceRun) {
        await vscode.window.showInformationMessage('No active voice capture is running.');
        return;
    }

    const run = currentVoiceRun;
    clearIdleResetTimer();
    const elapsed = formatElapsed(voiceState.getSnapshot().elapsedMs);
    run.stopRequestedAt = Date.now();
    logRun(run, `stop requested after ${elapsed}`);
    voiceState.transition(VoicePhase.TRANSCRIBING, {
        title: 'Stopping recording',
        detail: `Stopped after ${elapsed}. Finalizing the live transcript...`
    });
    run.recordingSession.stop();
}

async function cancelVoiceCapture() {
    if (!currentVoiceRun) {
        await vscode.window.showInformationMessage('No active voice capture is running.');
        return;
    }

    const run = currentVoiceRun;
    logRun(run, 'cancel command invoked');
    currentVoiceRun = null;
    markRunCanceled(run, 'cancel command');
    run.abortController.abort();
    run.recordingSession?.cancel();
    run.sttSession?.cancel('cancel command');
    clearIdleResetTimer();
    clearWaitAnimation();
    voiceState.transition(VoicePhase.IDLE, {
        title: 'Ready',
        detail: 'Voice capture canceled.'
    });
    await vscode.window.showInformationMessage('Voice capture canceled.');
}

async function showVoiceStatus() {
    const snapshot = voiceState.getSnapshot();
    if (snapshot.phase === VoicePhase.DONE && snapshot.finalText) {
        await vscode.env.clipboard.writeText(snapshot.finalText);
        await vscode.window.showInformationMessage('Final text copied to the clipboard again.');
        return;
    }

    if (snapshot.phase === VoicePhase.ERROR) {
        await vscode.window.showErrorMessage(
            snapshot.errorMessage || 'Voice capture failed.'
        );
        return;
    }

    await vscode.window.showInformationMessage(`${snapshot.title}: ${snapshot.detail}`);
}

async function clearKeysWithConfirmation(context) {
    const answer = await vscode.window.showWarningMessage(
        `Delete the saved SinusoidLabs and OpenRouter API keys from ${BRAND_NAME}?`,
        { modal: true },
        'Delete Keys'
    );

    if (answer !== 'Delete Keys') {
        return;
    }

    await clearSavedApiKeys(context);
    await vscode.window.showInformationMessage('Saved API keys were cleared.');
}

function activate(context) {
    outputChannel = vscode.window.createOutputChannel(BRAND_NAME);
    logExtension('activate called');
    voiceState = new VoiceStateStore();
    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBarItem.name = `${BRAND_NAME} Voice`;
    updateStatusBar(voiceState.getSnapshot());

    const stateSubscription = voiceState.onDidChange((snapshot) => {
        const signature = [
            snapshot.phase,
            snapshot.title,
            snapshot.detail,
            snapshot.errorMessage ? 'has-error' : 'no-error',
            snapshot.rawTranscript.length,
            snapshot.finalText.length
        ].join('|');
        if (signature !== lastLoggedSnapshotSignature) {
            lastLoggedSnapshotSignature = signature;
            logLine(
                `[state] phase=${snapshot.phase} title="${snapshot.title}" detail="${snapshot.detail}" rawChars=${snapshot.rawTranscript.length} finalChars=${snapshot.finalText.length} error=${snapshot.errorMessage ? 'yes' : 'no'}`
            );
        }
        updateStatusBar(snapshot);
    });

    const subscriptions = [
        vscode.commands.registerCommand(
            'cursorChatCopy.copyCurrentConversation',
            copyCurrentConversation
        ),
        vscode.commands.registerCommand('cursorChatCopy.startVoiceCapture', () =>
            startVoiceCapture(context)
        ),
        vscode.commands.registerCommand('cursorChatCopy.stopVoiceCapture', stopVoiceCapture),
        vscode.commands.registerCommand('cursorChatCopy.cancelVoiceCapture', cancelVoiceCapture),
        vscode.commands.registerCommand('cursorChatCopy.showVoiceProcessing', showVoiceStatus),
        vscode.commands.registerCommand('cursorChatCopy.showVoiceDone', showVoiceStatus),
        vscode.commands.registerCommand('cursorChatCopy.showVoiceError', showVoiceStatus),
        vscode.commands.registerCommand('cursorChatCopy.setSinusoidApiKey', async () => {
            await setSinusoidApiKey(context);
            await vscode.window.showInformationMessage('SinusoidLabs API key saved.');
        }),
        vscode.commands.registerCommand('cursorChatCopy.setOpenRouterApiKey', async () => {
            await setOpenRouterApiKey(context);
            await vscode.window.showInformationMessage('OpenRouter API key saved.');
        }),
        vscode.commands.registerCommand('cursorChatCopy.clearSavedApiKeys', () =>
            clearKeysWithConfirmation(context)
        ),
        outputChannel,
        stateSubscription,
        statusBarItem
    ];

    context.subscriptions.push(...subscriptions);
}

function deactivate() {
    logExtension(`deactivate called currentRun=${currentVoiceRun?.id ?? 'none'}`);
    clearIdleResetTimer();
    clearWaitAnimation();

    if (currentVoiceRun) {
        markRunCanceled(currentVoiceRun, 'extension deactivation');
        currentVoiceRun.abortController.abort();
        currentVoiceRun.recordingSession?.cancel();
        currentVoiceRun.sttSession?.cancel('extension deactivation');
        currentVoiceRun = null;
    }

    if (voiceState) {
        voiceState.dispose();
        voiceState = null;
    }

    if (outputChannel) {
        outputChannel.dispose();
        outputChannel = null;
    }

    if (statusBarItem) {
        statusBarItem.dispose();
        statusBarItem = null;
    }
}

module.exports = {
    activate,
    deactivate
};

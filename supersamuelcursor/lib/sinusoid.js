'use strict';

const WebSocket = require('ws');
const { appendTimestampedLine } = require('./logging');

class TranscriptAssembler {
    constructor() {
        this.committedText = '';
        this.interimText = '';
        this.endpointCount = 0;
        this.filteredTokens = new Set(['<|end|>', '<|endoftext|>', '<|start|>']);
    }

    apply(tokens, finished) {
        const committedParts = [];
        const interimParts = [];
        let endpointDetected = false;

        for (const token of tokens) {
            const rawText = typeof token?.text === 'string' ? token.text : '';
            const trimmed = rawText.trim();

            if (trimmed === '<|end|>') {
                endpointDetected = true;
                this.endpointCount += 1;
                continue;
            }

            if (this.filteredTokens.has(trimmed)) {
                continue;
            }

            if (token?.is_committed) {
                committedParts.push(rawText);
            } else {
                interimParts.push(rawText);
            }
        }

        if (committedParts.length > 0) {
            this.committedText += committedParts.join('');
        }

        this.interimText = interimParts.join('');

        return {
            committedText: this.committedText,
            interimText: this.interimText,
            combinedText: `${this.committedText}${this.interimText}`,
            finished: Boolean(finished),
            endpointDetected,
            endpointCount: this.endpointCount
        };
    }

    currentCombined() {
        return `${this.committedText}${this.interimText}`;
    }
}

function createAbortError(message = 'Voice capture canceled.') {
    const error = new Error(message);
    error.name = 'AbortError';
    return error;
}

function log(outputChannel, logPrefix, message) {
    const prefix = logPrefix ? `${logPrefix} [sinusoid]` : '[sinusoid]';
    appendTimestampedLine(outputChannel, prefix, message);
}

async function fetchToken(apiKey, signal) {
    const response = await fetch('https://api.sinusoidlabs.com/v1/stt/token', {
        method: 'POST',
        signal,
        headers: {
            'Authorization': `Bearer ${apiKey}`
        }
    });

    const payload = await response.json().catch(() => null);
    if (!response.ok) {
        const message =
            payload?.detail ||
            payload?.error ||
            payload?.message ||
            `SinusoidLabs token request failed with HTTP ${response.status}`;
        throw new Error(message);
    }

    if (!payload?.token) {
        throw new Error('SinusoidLabs token response did not include a token.');
    }

    return payload.token;
}

function wait(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function withTimeout(promise, ms, message) {
    let timer = null;
    return Promise.race([
        promise,
        new Promise((_, reject) => {
            timer = setTimeout(() => reject(new Error(message)), ms);
        })
    ]).finally(() => {
        if (timer) {
            clearTimeout(timer);
        }
    });
}

function sendMessage(socket, data) {
    return new Promise((resolve, reject) => {
        socket.send(data, (error) => {
            if (error) {
                reject(error);
                return;
            }

            resolve();
        });
    });
}

function normalizeMessageData(data) {
    if (typeof data === 'string') {
        return data;
    }

    if (Buffer.isBuffer(data)) {
        return data.toString('utf8');
    }

    if (Array.isArray(data)) {
        return Buffer.concat(data).toString('utf8');
    }

    return Buffer.from(data).toString('utf8');
}

function createRealtimeTranscriptionSession({
    apiKey,
    model,
    outputChannel,
    logPrefix,
    onSnapshot
}) {
    const assembler = new TranscriptAssembler();

    let socket = null;
    let started = false;
    let canceled = false;
    let finished = false;
    let hasSentFinish = false;
    let terminalError = null;
    let lastActivityAt = Date.now();
    let lastSnapshot = {
        committedText: '',
        interimText: '',
        combinedText: '',
        finished: false,
        endpointDetected: false,
        endpointCount: 0
    };
    let sendQueue = Promise.resolve();

    function markTerminalError(error) {
        if (!terminalError) {
            terminalError = error instanceof Error ? error : new Error(String(error));
        }
    }

    function ensureStarted() {
        if (!started || !socket) {
            throw new Error('Sinusoid realtime session is not started.');
        }
    }

    async function start({ signal } = {}) {
        if (signal?.aborted) {
            throw createAbortError();
        }

        const token = await fetchToken(apiKey, signal);

        const ws = new WebSocket('wss://api.sinusoidlabs.com/v1/stt/stream');
        socket = ws;

        ws.on('message', (data) => {
            try {
                lastActivityAt = Date.now();

                const payload = JSON.parse(normalizeMessageData(data));
                if (payload.error_code) {
                    const error = new Error(payload.error_message || payload.error_code);
                    markTerminalError(error);
                    log(outputChannel, logPrefix, `server error ${error.message}`);
                    return;
                }

                lastSnapshot = assembler.apply(payload.tokens || [], payload.finished || false);
                if (lastSnapshot.finished) {
                    finished = true;
                }

                onSnapshot?.(lastSnapshot);
            } catch (error) {
                markTerminalError(error);
                log(
                    outputChannel,
                    logPrefix,
                    `message parse failed ${error instanceof Error ? error.message : String(error)}`
                );
            }
        });

        ws.on('error', (error) => {
            markTerminalError(error);
            log(outputChannel, logPrefix, `websocket error ${error.message}`);
        });

        ws.on('close', (code, reasonBuffer) => {
            const reason =
                typeof reasonBuffer === 'string'
                    ? reasonBuffer
                    : Buffer.isBuffer(reasonBuffer)
                      ? reasonBuffer.toString('utf8')
                      : '';
            if (!finished && !canceled && !terminalError && !hasSentFinish) {
                log(
                    outputChannel,
                    logPrefix,
                    `websocket closed unexpectedly code=${code} reason=${reason || '(none)'}`
                );
                markTerminalError(new Error('SinusoidLabs websocket closed unexpectedly.'));
            }
        });

        await withTimeout(
            new Promise((resolve, reject) => {
                ws.once('open', resolve);
                ws.once('error', reject);
            }),
            10000,
            'SinusoidLabs websocket did not open in time.'
        );

        if (signal?.aborted) {
            throw createAbortError();
        }

        await sendMessage(
            ws,
            JSON.stringify({
                token,
                model,
                audio_format: 'pcm_s16le',
                sample_rate: 16000,
                num_channels: 1
            })
        );
        started = true;
    }

    function sendAudioChunk(data) {
        if (!started || !socket || canceled || !data || data.length === 0) {
            return;
        }

        const chunk = Buffer.isBuffer(data) ? data : Buffer.from(data);
        sendQueue = sendQueue
            .then(async () => {
                if (terminalError) {
                    throw terminalError;
                }

                await sendMessage(socket, chunk);
            })
            .catch((error) => {
                markTerminalError(error);
                log(
                    outputChannel,
                    logPrefix,
                    `audio chunk send failed ${error instanceof Error ? error.message : String(error)}`
                );
            });
    }

    async function finishAndWait({ finalizationTailMs, signal } = {}) {
        ensureStarted();

        if (signal?.aborted) {
            throw createAbortError();
        }

        await sendQueue;
        if (terminalError) {
            throw terminalError;
        }

        if (!hasSentFinish) {
            hasSentFinish = true;
            await sendMessage(socket, '');
        }

        const quietWindowMs = Math.max(finalizationTailMs ?? 1800, 300);
        const maxWaitMs = Math.max(quietWindowMs * 4, 10000);
        const absoluteDeadline = Date.now() + maxWaitMs;

        while (Date.now() < absoluteDeadline) {
            if (signal?.aborted) {
                throw createAbortError();
            }

            if (terminalError) {
                throw terminalError;
            }

            if (finished) {
                return assembler.currentCombined().trim();
            }

            const combined = assembler.currentCombined().trim();
            const quietForMs = Date.now() - lastActivityAt;
            if (combined && quietForMs >= quietWindowMs) {
                log(
                    outputChannel,
                    logPrefix,
                    `websocket quiet for ${quietForMs}ms, returning best available transcript endpointCount=${lastSnapshot.endpointCount}`
                );
                return combined;
            }

            await wait(100);
        }

        const fallback = assembler.currentCombined().trim();
        if (!fallback) {
            throw new Error('SinusoidLabs returned an empty transcript.');
        }

        log(
            outputChannel,
            logPrefix,
            'finalization timeout reached, returning best effort transcript'
        );
        return fallback;
    }

    function cancel() {
        canceled = true;
        try {
            socket?.close();
        } catch {
            // Ignore socket shutdown failures during cancellation.
        }
    }

    function getLastSnapshot() {
        return { ...lastSnapshot };
    }

    return {
        start,
        sendAudioChunk,
        finishAndWait,
        cancel,
        getLastSnapshot
    };
}

module.exports = {
    createRealtimeTranscriptionSession
};

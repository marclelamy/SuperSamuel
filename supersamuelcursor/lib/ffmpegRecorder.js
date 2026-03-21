'use strict';

const fs = require('fs');
const { execSync, spawn } = require('child_process');
const { appendTimestampedLine } = require('./logging');

const DEFAULT_AUDIO_INPUT = ':0';

function findBinary(explicitPath, binaryName, extraCandidates = []) {
    const candidates = [];
    if (explicitPath && explicitPath.trim()) {
        candidates.push(explicitPath.trim());
    }
    candidates.push(...extraCandidates);

    for (const candidate of candidates) {
        if (candidate && fs.existsSync(candidate)) {
            return candidate;
        }
    }

    try {
        const locator = process.platform === 'win32' ? `where ${binaryName}` : `which ${binaryName}`;
        const result = execSync(locator, {
            encoding: 'utf8',
            stdio: ['pipe', 'pipe', 'pipe']
        }).trim();
        const discovered = result.split(/\r?\n/)[0];
        if (discovered && fs.existsSync(discovered)) {
            return discovered;
        }
    } catch {
        return null;
    }

    return null;
}

function findFfmpeg(explicitPath) {
    const extraCandidates =
        process.platform === 'darwin'
            ? ['/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg', '/usr/bin/ffmpeg']
            : [];

    return findBinary(explicitPath, 'ffmpeg', extraCandidates);
}

function log(outputChannel, logPrefix, message) {
    const prefix = logPrefix ? `${logPrefix} [ffmpeg]` : '[ffmpeg]';
    appendTimestampedLine(outputChannel, prefix, message);
}

function startFfmpegStreaming({
    ffmpegPath,
    outputChannel,
    logPrefix,
    onChunk
}) {
    const resolvedFfmpeg = findFfmpeg(ffmpegPath);
    if (!resolvedFfmpeg) {
        throw new Error('ffmpeg was not found. Set superSamuelCursor.ffmpegPath or install ffmpeg.');
    }

    const args = [
        '-hide_banner',
        '-loglevel',
        'error',
        '-f',
        'avfoundation',
        '-i',
        DEFAULT_AUDIO_INPUT,
        '-ac',
        '1',
        '-ar',
        '16000',
        '-f',
        's16le',
        '-acodec',
        'pcm_s16le',
        'pipe:1'
    ];

    const child = spawn(resolvedFfmpeg, args, {
        stdio: ['pipe', 'pipe', 'pipe']
    });

    let stopRequested = false;
    let stderrOutput = '';
    let exited = false;
    let forceStopTimer = null;
    let streamedBytes = 0;
    let chunkDispatchError = null;
    let pendingBytes = Buffer.alloc(0);
    const targetChunkBytes = 3200;

    child.stderr.setEncoding('utf8');
    child.stderr.on('data', (chunk) => {
        const text = String(chunk);
        stderrOutput += text;
    });

    child.stdout.on('data', (chunk) => {
        const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        streamedBytes += buffer.length;
        pendingBytes = Buffer.concat([pendingBytes, buffer]);

        while (pendingBytes.length >= targetChunkBytes) {
            const chunkToSend = Buffer.from(pendingBytes.subarray(0, targetChunkBytes));
            pendingBytes = Buffer.from(pendingBytes.subarray(targetChunkBytes));

            try {
                onChunk?.(chunkToSend);
            } catch (error) {
                chunkDispatchError = error instanceof Error ? error : new Error(String(error));
                log(outputChannel, logPrefix, `chunk dispatch failed ${chunkDispatchError.message}`);
                child.kill('SIGTERM');
                break;
            }
        }
    });

    const completion = new Promise((resolve, reject) => {
        child.on('error', (error) => {
            log(outputChannel, logPrefix, `process error ${error.message}`);
            reject(error);
        });

        child.on('close', (code) => {
            exited = true;
            if (forceStopTimer) {
                clearTimeout(forceStopTimer);
                forceStopTimer = null;
            }

            if (!chunkDispatchError && pendingBytes.length > 0) {
                try {
                    onChunk?.(Buffer.from(pendingBytes));
                    pendingBytes = Buffer.alloc(0);
                } catch (error) {
                    chunkDispatchError = error instanceof Error ? error : new Error(String(error));
                    log(outputChannel, logPrefix, `final chunk dispatch failed ${chunkDispatchError.message}`);
                }
            }

            if (chunkDispatchError) {
                reject(chunkDispatchError);
                return;
            }

            if (stopRequested && streamedBytes > 0) {
                resolve({
                    byteLength: streamedBytes,
                    cleanup() {}
                });
                return;
            }

            const message =
                stderrOutput.trim() ||
                `ffmpeg exited with code ${code ?? 'unknown'} before producing audio.`;
            reject(new Error(message));
        });
    });

    return {
        stop() {
            if (!stopRequested) {
                stopRequested = true;
                child.stdin.write('q\n');
                child.stdin.end();
                forceStopTimer = setTimeout(() => {
                    if (!exited) {
                        log(outputChannel, logPrefix, 'graceful stop timed out, sending SIGINT');
                        child.kill('SIGINT');
                    }
                }, 2500);
            }
        },
        cancel() {
            stopRequested = true;
            child.kill('SIGTERM');
        },
        completion
    };
}

module.exports = {
    findFfmpeg,
    startFfmpegStreaming
};

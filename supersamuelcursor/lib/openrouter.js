'use strict';

const { buildRewriteMessages } = require('./prompt');
const { appendTimestampedLine, formatDurationMs } = require('./logging');

function readContentText(content) {
    if (typeof content === 'string') {
        return content.trim();
    }

    if (Array.isArray(content)) {
        return content
            .map((part) => {
                if (typeof part === 'string') {
                    return part;
                }

                if (part?.type === 'text' && typeof part.text === 'string') {
                    return part.text;
                }

                return '';
            })
            .join('\n')
            .trim();
    }

    return '';
}

function log(outputChannel, logPrefix, message) {
    const prefix = logPrefix ? `${logPrefix} [openrouter]` : '[openrouter]';
    appendTimestampedLine(outputChannel, prefix, message);
}

async function rewriteTranscript({
    apiKey,
    baseUrl,
    model,
    temperature,
    contextMarkdown,
    rawTranscript,
    rewriteInstruction,
    signal,
    outputChannel,
    logPrefix
}) {
    const requestStartedAt = Date.now();
    const messages = buildRewriteMessages({
        contextMarkdown,
        rawTranscript,
        rewriteInstruction
    });
    let response;
    try {
        response = await fetch(baseUrl, {
            method: 'POST',
            signal,
            headers: {
                'Authorization': `Bearer ${apiKey}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                model,
                temperature,
                messages
            })
        });
    } catch (error) {
        log(
            outputChannel,
            logPrefix,
            `network error after ${formatDurationMs(Date.now() - requestStartedAt)} ${error instanceof Error ? error.message : String(error)}`
        );
        throw error;
    }
    const payload = await response.json().catch(() => null);
    if (!response.ok) {
        const message =
            payload?.error?.message ||
            payload?.message ||
            `OpenRouter request failed with HTTP ${response.status}`;
        log(
            outputChannel,
            logPrefix,
            `request failed duration=${formatDurationMs(Date.now() - requestStartedAt)} ${message}`
        );
        throw new Error(message);
    }

    const text = readContentText(payload?.choices?.[0]?.message?.content);
    if (!text) {
        log(
            outputChannel,
            logPrefix,
            `request succeeded but returned empty content duration=${formatDurationMs(Date.now() - requestStartedAt)}`
        );
        throw new Error('OpenRouter returned an empty response.');
    }

    return text;
}

module.exports = {
    rewriteTranscript
};

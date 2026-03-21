'use strict';

function pad(value, width = 2) {
    return String(value).padStart(width, '0');
}

function formatLogTimestamp(timestampMs = Date.now()) {
    const date = timestampMs instanceof Date ? timestampMs : new Date(timestampMs);
    return [
        date.getFullYear(),
        pad(date.getMonth() + 1),
        pad(date.getDate())
    ].join('-') +
        ' ' +
        [pad(date.getHours()), pad(date.getMinutes()), pad(date.getSeconds())].join(':') +
        `.${pad(date.getMilliseconds(), 3)}`;
}

function formatDurationMs(durationMs) {
    const safeDurationMs = Math.max(0, Math.round(Number(durationMs) || 0));
    if (safeDurationMs < 1000) {
        return `${safeDurationMs}ms`;
    }

    const totalSeconds = Math.floor(safeDurationMs / 1000);
    const milliseconds = pad(safeDurationMs % 1000, 3);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;

    if (minutes > 0) {
        return `${minutes}m ${pad(seconds)}.${milliseconds}s`;
    }

    return `${seconds}.${milliseconds}s`;
}

function formatNumberWithSeparators(value) {
    return Math.max(0, Math.round(Number(value) || 0)).toLocaleString('en-US');
}

function formatRelativeElapsedMs(durationMs) {
    const safeDurationMs = Math.max(0, Math.round(Number(durationMs) || 0));
    const totalSeconds = Math.floor(safeDurationMs / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const milliseconds = safeDurationMs % 1000;
    return `${pad(minutes)}:${pad(seconds)}.${pad(milliseconds, 3)}`;
}

function appendTimestampedLine(outputChannel, prefix, message, timestampMs = Date.now()) {
    const prefixPart = prefix ? ` ${prefix}` : '';
    outputChannel?.appendLine(`[${formatLogTimestamp(timestampMs)}]${prefixPart} ${message}`);
}

module.exports = {
    appendTimestampedLine,
    formatDurationMs,
    formatLogTimestamp,
    formatNumberWithSeparators,
    formatRelativeElapsedMs
};

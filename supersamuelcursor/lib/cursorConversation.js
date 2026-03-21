'use strict';

const {
    readCursorDiskKVJson,
    readCursorDiskKVRowsByKeys,
    readCursorDiskKVRowsByPrefix,
    readItemTableJson
} = require('./sqlite');

function emitTiming(onTiming, step, startedAt, detail = '') {
    onTiming?.({
        step,
        durationMs: Date.now() - startedAt,
        detail
    });
}

function timeSyncStep(onTiming, step, operation, successDetail) {
    const startedAt = Date.now();
    const result = operation();
    const resolvedSuccessDetail =
        typeof successDetail === 'function' ? successDetail(result) : successDetail;
    emitTiming(onTiming, step, startedAt, resolvedSuccessDetail || '');
    return result;
}

function normalizeLabel(value) {
    return String(value || '').trim().toLowerCase();
}

function uniqueValues(values) {
    return Array.from(new Set(values.filter(Boolean)));
}

function selectComposerId(composerState, activeTabLabel) {
    const allComposers = Array.isArray(composerState?.allComposers)
        ? composerState.allComposers
        : [];

    const byId = new Map();
    for (const composer of allComposers) {
        if (composer?.composerId) {
            byId.set(composer.composerId, composer);
        }
    }

    const lastFocused = Array.isArray(composerState?.lastFocusedComposerIds)
        ? composerState.lastFocusedComposerIds
        : [];
    const selected = Array.isArray(composerState?.selectedComposerIds)
        ? composerState.selectedComposerIds
        : [];

    const normalizedActiveTabLabel = normalizeLabel(activeTabLabel);
    const activeTabMatches = normalizedActiveTabLabel
        ? allComposers
              .filter((composer) => normalizeLabel(composer?.name) === normalizedActiveTabLabel)
              .map((composer) => composer.composerId)
        : [];

    const sortedByRecency = [...allComposers]
        .sort((left, right) => (right?.lastUpdatedAt || 0) - (left?.lastUpdatedAt || 0))
        .map((composer) => composer.composerId);

    const candidates = uniqueValues([
        ...activeTabMatches.filter((id) => lastFocused.includes(id)),
        ...activeTabMatches.filter((id) => selected.includes(id)),
        ...activeTabMatches,
        ...lastFocused,
        ...selected,
        ...sortedByRecency
    ]);

    return candidates.find((id) => byId.has(id)) || null;
}

function extractBubbleId(key) {
    if (!key) {
        return null;
    }

    const parts = key.split(':');
    if (parts.length < 3) {
        return null;
    }

    return parts.slice(2).join(':');
}

function extractBubbleText(bubble) {
    const candidateKeys = ['text', 'rawText', 'markdown', 'content', 'summary', 'title'];
    for (const key of candidateKeys) {
        const value = bubble?.[key];
        if (typeof value === 'string' && value.trim()) {
            return value.trim();
        }
    }

    const delegateText = bubble?.delegate?.a;
    if (typeof delegateText === 'string' && delegateText.trim()) {
        return delegateText.trim();
    }

    return '';
}

function bubbleRole(headerType, bubbleType) {
    const resolvedType = bubbleType ?? headerType;
    if (resolvedType === 1) {
        return 'user';
    }

    if (resolvedType === 2) {
        return 'assistant';
    }

    return 'other';
}

function reconstructMessages(composerRecord, bubbleRows, onTiming) {
    const bubbleMap = timeSyncStep(
        onTiming,
        'messages.bubble_map',
        () => {
            const map = new Map();
            for (const row of bubbleRows) {
                const bubbleId = extractBubbleId(row.key);
                if (!bubbleId || !row.value) {
                    continue;
                }

                try {
                    map.set(bubbleId, JSON.parse(row.value));
                } catch {
                    // Skip malformed bubble payloads.
                }
            }

            return map;
        },
        (map) => `rows=${bubbleRows.length} parsed=${map.size}`
    );

    const headers = Array.isArray(composerRecord?.fullConversationHeadersOnly)
        ? composerRecord.fullConversationHeadersOnly
        : [];

    if (headers.length > 0) {
        return timeSyncStep(
            onTiming,
            'messages.from_headers',
            () => {
                const messages = [];
                for (const header of headers) {
                    const bubble = bubbleMap.get(header?.bubbleId);
                    if (!bubble) {
                        continue;
                    }

                    const text = extractBubbleText(bubble);
                    if (!text) {
                        continue;
                    }

                    const role = bubbleRole(header?.type, bubble?.type);
                    if (role === 'other') {
                        continue;
                    }

                    messages.push({
                        role,
                        text,
                        bubbleId: header?.bubbleId || bubble?.bubbleId || null
                    });
                }

                return messages;
            },
            (messages) => `headers=${headers.length} messages=${messages.length}`
        );
    }

    const fallbackBubbles = timeSyncStep(
        onTiming,
        'messages.fallback_parse',
        () => {
            const entries = [];
            for (const row of bubbleRows) {
                const bubbleId = extractBubbleId(row.key);
                if (!bubbleId || !row.value) {
                    continue;
                }

                try {
                    const bubble = JSON.parse(row.value);
                    entries.push({
                        bubbleId,
                        bubble
                    });
                } catch {
                    // Skip malformed bubble payloads.
                }
            }

            return entries;
        },
        (entries) => `fallbackBubbles=${entries.length}`
    );

    return timeSyncStep(
        onTiming,
        'messages.fallback_sort_collect',
        () => {
            const messages = [];

            fallbackBubbles.sort((left, right) => {
                const leftCreatedAt = Date.parse(left.bubble?.createdAt || '') || 0;
                const rightCreatedAt = Date.parse(right.bubble?.createdAt || '') || 0;
                return leftCreatedAt - rightCreatedAt;
            });

            for (const entry of fallbackBubbles) {
                const text = extractBubbleText(entry.bubble);
                if (!text) {
                    continue;
                }

                const role = bubbleRole(undefined, entry.bubble?.type);
                if (role === 'other') {
                    continue;
                }

                messages.push({
                    role,
                    text,
                    bubbleId: entry.bubbleId
                });
            }

            return messages;
        },
        (messages) => `messages=${messages.length}`
    );
}

function loadCurrentConversation({
    workspaceDbPath,
    globalDbPath,
    activeTabLabel,
    workspaceFolderPath,
    onTiming
}) {
    const composerState = timeSyncStep(
        onTiming,
        'workspace.composer_state',
        () => readItemTableJson(workspaceDbPath, 'composer.composerData'),
        (state) => `composers=${Array.isArray(state?.allComposers) ? state.allComposers.length : 0}`
    );
    if (!composerState) {
        throw new Error('Cursor composer metadata was not found for the current workspace.');
    }

    const composerId = timeSyncStep(
        onTiming,
        'composer.select',
        () => selectComposerId(composerState, activeTabLabel),
        (id) => (id ? `composerId=${id}` : 'composerId=(none)')
    );
    if (!composerId) {
        throw new Error('Could not determine the current Cursor conversation.');
    }

    const composerMeta = Array.isArray(composerState.allComposers)
        ? composerState.allComposers.find((composer) => composer?.composerId === composerId)
        : null;

    const composerRecord = timeSyncStep(
        onTiming,
        'global.composer_record',
        () => readCursorDiskKVJson(globalDbPath, `composerData:${composerId}`),
        (record) =>
            `headers=${Array.isArray(record?.fullConversationHeadersOnly) ? record.fullConversationHeadersOnly.length : 0}`
    );
    if (!composerRecord) {
        throw new Error('Could not load the current conversation payload from Cursor storage.');
    }

    const headersForExactLookup = Array.isArray(composerRecord.fullConversationHeadersOnly)
        ? composerRecord.fullConversationHeadersOnly
        : [];
    const exactBubbleKeys = uniqueValues(
        headersForExactLookup.map((header) =>
            header?.bubbleId ? `bubbleId:${composerId}:${header.bubbleId}` : null
        )
    );

    const bubbleRows =
        exactBubbleKeys.length > 0
            ? timeSyncStep(
                  onTiming,
                  'global.bubble_rows_exact',
                  () => readCursorDiskKVRowsByKeys(globalDbPath, exactBubbleKeys),
                  (rows) => `keys=${exactBubbleKeys.length} rows=${rows.length}`
              )
            : timeSyncStep(
                  onTiming,
                  'global.bubble_rows_prefix',
                  () => readCursorDiskKVRowsByPrefix(globalDbPath, `bubbleId:${composerId}:`),
                  (rows) => `rows=${rows.length}`
              );
    const messages = reconstructMessages(composerRecord, bubbleRows, onTiming);
    if (messages.length === 0) {
        throw new Error('No user or assistant messages were found in the current conversation.');
    }

    return {
        composerId,
        title: composerMeta?.name || 'Untitled conversation',
        subtitle: composerMeta?.subtitle || '',
        workspaceFolderPath,
        messages
    };
}

module.exports = {
    loadCurrentConversation,
    reconstructMessages,
    selectComposerId
};

'use strict';

function buildRewriteMessages({ contextMarkdown, rawTranscript, rewriteInstruction }) {
    return [
        {
            role: 'system',
            content:
                'You convert messy spoken dictation into clean written text for coding conversations. ' +
                'Treat the raw transcript as the source of truth, but rewrite it into a natural, readable sentence-by-sentence dictation result. ' +
                'Remove filler words and speech artifacts such as "um", "uh", "like" when used as filler, "you know", repeated words, false starts, self-corrections, stutters, and obvious recognition noise. ' +
                'Preserve all concrete meaning, technical details, intent, uncertainty, and important qualifiers. ' +
                'Do not summarize, shorten for brevity, add new facts, answer the conversation, or invent content from the context. ' +
                'Use the conversation context only to fix an obviously misrecognized name, code symbol, product name, or technical term. ' +
                'Example: "um can you like open the package json and uh change the model" becomes "Can you open the package.json and change the model?" ' +
                'Example: "i think we should, we should maybe keep that part" becomes "I think we should maybe keep that part." ' +
                'Return only the cleaned transcript.'
        },
        {
            role: 'user',
            content: [
                'Raw transcript to rewrite (source of truth):',
                rawTranscript.trim(),
                '',
                'Rewrite rules:',
                rewriteInstruction,
                '',
                'Optional reference context. Use only to resolve an obviously misrecognized technical term or name:',
                contextMarkdown || '(no conversation context provided)'
            ].join('\n')
        }
    ];
}

module.exports = {
    buildRewriteMessages
};

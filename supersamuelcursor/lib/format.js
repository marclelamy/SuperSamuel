'use strict';

function roleHeading(role) {
    return role === 'assistant' ? 'Assistant' : 'User';
}

function formatConversationMarkdown(conversation) {
    const lines = [];
    lines.push(`# Cursor Conversation: ${conversation.title}`);
    lines.push('');

    for (const message of conversation.messages) {
        lines.push(`## ${roleHeading(message.role)}`);
        lines.push('');
        lines.push(message.text.trim());
        lines.push('');
    }

    return `${lines.join('\n').trim()}\n`;
}

module.exports = {
    formatConversationMarkdown
};

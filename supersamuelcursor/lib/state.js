'use strict';

const vscode = require('vscode');

const VoicePhase = Object.freeze({
    IDLE: 'idle',
    RECORDING: 'recording',
    TRANSCRIBING: 'transcribing',
    CLEANUP: 'cleanup',
    DONE: 'done',
    ERROR: 'error'
});

function getIdleDetail() {
    return process.platform === 'darwin'
        ? 'Press Shift+Option+Space or click the Voice button in the status bar to start recording.'
        : 'Press Ctrl+Alt+Shift+R or click the Voice button in the status bar to start recording.';
}

class VoiceStateStore {
    constructor() {
        this.listeners = new Set();
        this.timer = null;
        this.snapshot = {
            phase: VoicePhase.IDLE,
            title: 'Ready',
            detail: getIdleDetail(),
            elapsedMs: 0,
            rawTranscript: '',
            finalText: '',
            errorMessage: ''
        };

        this.applyContexts();
    }

    onDidChange(listener) {
        this.listeners.add(listener);
        listener(this.getSnapshot());

        return {
            dispose: () => this.listeners.delete(listener)
        };
    }

    getSnapshot() {
        return { ...this.snapshot };
    }

    transition(phase, updates = {}) {
        if (phase === VoicePhase.RECORDING && this.snapshot.phase !== VoicePhase.RECORDING) {
            this.startTimer();
        } else if (phase !== VoicePhase.RECORDING && this.snapshot.phase === VoicePhase.RECORDING) {
            this.stopTimer();
        }

        this.snapshot = {
            ...this.snapshot,
            ...updates,
            phase
        };

        if (phase === VoicePhase.IDLE) {
            this.snapshot.elapsedMs = 0;
            this.snapshot.rawTranscript = '';
            this.snapshot.finalText = '';
            this.snapshot.errorMessage = '';
        }

        this.applyContexts();
        this.emit();
    }

    setData(updates) {
        this.snapshot = {
            ...this.snapshot,
            ...updates
        };
        this.emit();
    }

    dispose() {
        this.stopTimer();
        this.listeners.clear();
    }

    startTimer() {
        this.stopTimer();
        const recordingStartedAt = Date.now();
        this.snapshot.elapsedMs = 0;
        this.timer = setInterval(() => {
            this.snapshot = {
                ...this.snapshot,
                elapsedMs: Date.now() - recordingStartedAt
            };
            this.emit();
        }, 200);
    }

    stopTimer() {
        if (this.timer) {
            clearInterval(this.timer);
            this.timer = null;
        }
    }

    emit() {
        const snapshot = this.getSnapshot();
        for (const listener of this.listeners) {
            listener(snapshot);
        }
    }

    applyContexts() {
        void vscode.commands.executeCommand('setContext', 'cursorVoice.phase', this.snapshot.phase);
        void vscode.commands.executeCommand(
            'setContext',
            'cursorVoice.isBusy',
            this.snapshot.phase === VoicePhase.TRANSCRIBING || this.snapshot.phase === VoicePhase.CLEANUP
        );
    }
}

module.exports = {
    VoicePhase,
    VoiceStateStore
};

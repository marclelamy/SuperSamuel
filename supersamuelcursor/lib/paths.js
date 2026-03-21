'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { fileURLToPath } = require('url');

function getDefaultCursorUserDir() {
    if (process.platform === 'darwin') {
        return path.join(os.homedir(), 'Library', 'Application Support', 'Cursor');
    }

    if (process.platform === 'win32') {
        const appData =
            process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
        return path.join(appData, 'Cursor');
    }

    return path.join(os.homedir(), '.config', 'Cursor');
}

function resolveWorkspaceStorageDir() {
    const envPath = process.env.CURSOR_WORKSPACE_STORAGE;
    if (envPath && fs.existsSync(envPath)) {
        return envPath;
    }

    const remoteLinux = path.join(
        os.homedir(),
        '.cursor-server',
        'data',
        'User',
        'workspaceStorage'
    );
    if (fs.existsSync(remoteLinux)) {
        return remoteLinux;
    }

    return path.join(getDefaultCursorUserDir(), 'User', 'workspaceStorage');
}

function getGlobalDbPath() {
    return path.join(getDefaultCursorUserDir(), 'User', 'globalStorage', 'state.vscdb');
}

function normalizeFilePath(filePath) {
    if (!filePath) {
        return '';
    }

    let resolved = path.resolve(filePath);
    try {
        resolved = fs.realpathSync(resolved);
    } catch {
        // Keep the resolved path when the target is unavailable.
    }

    return process.platform === 'win32' ? resolved.toLowerCase() : resolved;
}

function parseWorkspaceFolder(folderValue) {
    if (!folderValue || typeof folderValue !== 'string') {
        return undefined;
    }

    try {
        if (folderValue.startsWith('file://')) {
            return normalizeFilePath(fileURLToPath(folderValue));
        }
    } catch {
        return undefined;
    }

    return normalizeFilePath(folderValue);
}

function readWorkspaceJson(workspaceHash) {
    const workspaceJsonPath = path.join(
        resolveWorkspaceStorageDir(),
        workspaceHash,
        'workspace.json'
    );

    if (!fs.existsSync(workspaceJsonPath)) {
        return null;
    }

    try {
        const raw = fs.readFileSync(workspaceJsonPath, 'utf8');
        return JSON.parse(raw);
    } catch {
        return null;
    }
}

function listWorkspaceCandidates() {
    const root = resolveWorkspaceStorageDir();
    if (!fs.existsSync(root)) {
        return [];
    }

    const entries = fs.readdirSync(root, { withFileTypes: true });
    const candidates = [];

    for (const entry of entries) {
        if (!entry.isDirectory()) {
            continue;
        }

        const dbPath = path.join(root, entry.name, 'state.vscdb');
        if (!fs.existsSync(dbPath)) {
            continue;
        }

        const workspaceJson = readWorkspaceJson(entry.name);
        const folderPath = parseWorkspaceFolder(workspaceJson?.folder);
        const stat = fs.statSync(dbPath);

        candidates.push({
            hash: entry.name,
            dbPath,
            folderPath,
            name: folderPath ? path.basename(folderPath) : entry.name,
            mtimeMs: stat.mtimeMs || 0
        });
    }

    candidates.sort((left, right) => right.mtimeMs - left.mtimeMs);
    return candidates;
}

function findWorkspaceForFolder(currentWorkspacePath) {
    const normalizedCurrentPath = normalizeFilePath(currentWorkspacePath);
    const candidates = listWorkspaceCandidates();

    if (!normalizedCurrentPath || candidates.length === 0) {
        return null;
    }

    const exactMatch = candidates.find(
        (candidate) => candidate.folderPath === normalizedCurrentPath
    );
    if (exactMatch) {
        return exactMatch;
    }

    const currentBasename = path.basename(normalizedCurrentPath);
    const basenameMatch = candidates.find(
        (candidate) => candidate.name === currentBasename
    );

    return basenameMatch || null;
}

module.exports = {
    findWorkspaceForFolder,
    getDefaultCursorUserDir,
    getGlobalDbPath,
    listWorkspaceCandidates,
    resolveWorkspaceStorageDir
};

'use strict';

const fs = require('fs');
const { execFileSync, execSync } = require('child_process');

function sqlEscapeLiteral(value) {
    return String(value).replace(/'/g, "''");
}

function hexToUtf8(hexValue) {
    const trimmed = String(hexValue || '').trim();
    if (!trimmed) {
        return null;
    }

    return Buffer.from(trimmed, 'hex').toString('utf8');
}

function findSqlite3() {
    const candidates =
        process.platform === 'win32'
            ? [
                  'C:\\sqlite3\\sqlite3.exe',
                  'C:\\sqlite\\sqlite3.exe',
                  'C:\\Program Files\\sqlite3\\sqlite3.exe',
                  'C:\\Program Files\\sqlite\\sqlite3.exe',
                  'C:\\Program Files (x86)\\sqlite3\\sqlite3.exe',
                  'C:\\Program Files (x86)\\sqlite\\sqlite3.exe'
              ]
            : [
                  '/usr/bin/sqlite3',
                  '/usr/local/bin/sqlite3',
                  '/bin/sqlite3',
                  '/opt/homebrew/bin/sqlite3'
              ];

    for (const candidate of candidates) {
        if (fs.existsSync(candidate)) {
            return candidate;
        }
    }

    try {
        const locator = process.platform === 'win32' ? 'where sqlite3' : 'which sqlite3';
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

function execSqlite(dbPath, input) {
    const sqlite3Path = findSqlite3();
    if (!sqlite3Path) {
        throw new Error('sqlite3 CLI not found. Install sqlite3 to use SuperSamuelCursor.');
    }

    if (!fs.existsSync(dbPath)) {
        throw new Error(`SQLite database not found: ${dbPath}`);
    }

    return execFileSync(sqlite3Path, ['-cmd', '.timeout 5000', dbPath], {
        input,
        encoding: 'utf8',
        maxBuffer: 256 * 1024 * 1024
    });
}

function queryHexRows(dbPath, sql, columnCount) {
    const separator = '\t';
    const input = ['.mode list', `.separator "${separator}"`, sql].join('\n') + '\n';
    const output = execSqlite(dbPath, input);
    const lines = output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);

    return lines.map((line) => {
        const columns = line.split(separator);
        while (columns.length < columnCount) {
            columns.push('');
        }

        return columns.slice(0, columnCount).map(hexToUtf8);
    });
}

function querySingleHexValue(dbPath, sql) {
    const rows = queryHexRows(dbPath, sql, 1);
    if (rows.length === 0) {
        return null;
    }

    return rows[0][0];
}

function readItemTableJson(dbPath, key) {
    const escapedKey = sqlEscapeLiteral(key);
    const sql = `SELECT hex(value) FROM ItemTable WHERE [key] = '${escapedKey}';`;
    const value = querySingleHexValue(dbPath, sql);
    return value ? JSON.parse(value) : null;
}

function readCursorDiskKVJson(dbPath, key) {
    const escapedKey = sqlEscapeLiteral(key);
    const sql = `SELECT hex(value) FROM cursorDiskKV WHERE [key] = '${escapedKey}';`;
    const value = querySingleHexValue(dbPath, sql);
    return value ? JSON.parse(value) : null;
}

function readCursorDiskKVRowsByPrefix(dbPath, prefix) {
    const escapedPrefix = sqlEscapeLiteral(prefix);
    const sql =
        `SELECT hex([key]), hex(value) ` +
        `FROM cursorDiskKV WHERE [key] LIKE '${escapedPrefix}%';`;

    return queryHexRows(dbPath, sql, 2).map(([key, value]) => ({
        key,
        value
    }));
}

function readCursorDiskKVRowsByKeys(dbPath, keys) {
    const normalizedKeys = Array.from(new Set((keys || []).filter(Boolean)));
    if (normalizedKeys.length === 0) {
        return [];
    }

    const chunkSize = 250;
    const rows = [];

    for (let index = 0; index < normalizedKeys.length; index += chunkSize) {
        const chunk = normalizedKeys.slice(index, index + chunkSize);
        const escapedKeys = chunk.map((key) => `'${sqlEscapeLiteral(key)}'`).join(', ');
        const sql =
            `SELECT hex([key]), hex(value) ` +
            `FROM cursorDiskKV WHERE [key] IN (${escapedKeys});`;

        rows.push(
            ...queryHexRows(dbPath, sql, 2).map(([key, value]) => ({
                key,
                value
            }))
        );
    }

    return rows;
}

module.exports = {
    findSqlite3,
    readCursorDiskKVJson,
    readCursorDiskKVRowsByKeys,
    readCursorDiskKVRowsByPrefix,
    readItemTableJson,
    sqlEscapeLiteral
};

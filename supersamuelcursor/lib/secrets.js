'use strict';

const vscode = require('vscode');

const SECRET_KEYS = Object.freeze({
    sinusoid: 'superSamuel.sinusoidApiKey',
    openRouter: 'superSamuel.openRouterApiKey'
});

async function promptForSecret(prompt) {
    const value = await vscode.window.showInputBox({
        prompt,
        password: true,
        ignoreFocusOut: true,
        validateInput: (input) => (input.trim() ? undefined : 'A value is required.')
    });

    if (!value) {
        throw new Error('Setup was cancelled.');
    }

    return value.trim();
}

async function resolveSecret(context, secretKey, envKeys, prompt) {
    const fromSecrets = await context.secrets.get(secretKey);
    if (fromSecrets) {
        return fromSecrets;
    }

    for (const envKey of envKeys) {
        const value = process.env[envKey]?.trim();
        if (value) {
            return value;
        }
    }

    const entered = await promptForSecret(prompt);
    await context.secrets.store(secretKey, entered);
    return entered;
}

async function setSecret(context, secretKey, prompt) {
    const entered = await promptForSecret(prompt);
    await context.secrets.store(secretKey, entered);
}

async function getSinusoidApiKey(context) {
    return resolveSecret(
        context,
        SECRET_KEYS.sinusoid,
        ['SUPERSAMUEL_SINUSOID_API_KEY', 'SUPERSAMUEL_API_KEY'],
        'Enter your SinusoidLabs API key'
    );
}

async function getOpenRouterApiKey(context) {
    return resolveSecret(
        context,
        SECRET_KEYS.openRouter,
        ['OPENROUTER_API_KEY'],
        'Enter your OpenRouter API key'
    );
}

async function setSinusoidApiKey(context) {
    await setSecret(context, SECRET_KEYS.sinusoid, 'Enter your SinusoidLabs API key');
}

async function setOpenRouterApiKey(context) {
    await setSecret(context, SECRET_KEYS.openRouter, 'Enter your OpenRouter API key');
}

async function clearSavedApiKeys(context) {
    await context.secrets.delete(SECRET_KEYS.sinusoid);
    await context.secrets.delete(SECRET_KEYS.openRouter);
}

module.exports = {
    clearSavedApiKeys,
    getOpenRouterApiKey,
    getSinusoidApiKey,
    setOpenRouterApiKey,
    setSinusoidApiKey
};

import { createServer } from "node:http";
import { resolve } from "node:path";
import { config as loadDotEnv } from "dotenv";

type TokenResponse = {
    token: string;
    expires_in: number;
};

type ErrorBody = {
    detail?: string;
    error?: string;
    message?: string;
};

const explicitPath = process.env.DOTENV_PATH;
if (explicitPath) {
    loadDotEnv({ path: explicitPath });
} else {
    // Try local broker .env first, then fallback to workspace root .env.
    loadDotEnv({ path: resolve(process.cwd(), ".env") });
    loadDotEnv({ path: resolve(process.cwd(), "../.env") });
}

const API_KEY = process.env.API_KEY;
const PORT = Number(process.env.BROKER_PORT ?? 8787);
const TOKEN_URL = "https://api.sinusoidlabs.com/v1/stt/token";

if (!API_KEY) {
    throw new Error("Missing API_KEY. Set it in ../.env or env vars.");
}

async function delay(ms: number): Promise<void> {
    await new Promise((resolveDelay) => setTimeout(resolveDelay, ms));
}

async function requestTokenWithRetry(maxRetries = 3): Promise<TokenResponse> {
    let attempt = 0;

    while (true) {
        const response = await fetch(TOKEN_URL, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${API_KEY}`,
            },
        });

        if (response.status === 429 && attempt < maxRetries) {
            const backoffMs = 1000 * Math.pow(2, attempt);
            attempt += 1;
            await delay(backoffMs);
            continue;
        }

        if (!response.ok) {
            const body = (await safeJson(response)) as ErrorBody | null;
            const detail = body?.detail ?? body?.error ?? body?.message ?? "Unknown error";
            throw new BrokerHttpError(response.status, detail);
        }

        const payload = (await response.json()) as TokenResponse;

        if (!payload.token || typeof payload.expires_in !== "number") {
            throw new BrokerHttpError(502, "Invalid token response shape");
        }

        return payload;
    }
}

async function safeJson(response: Response): Promise<unknown | null> {
    try {
        return await response.json();
    } catch {
        return null;
    }
}

class BrokerHttpError extends Error {
    public readonly status: number;

    constructor(status: number, message: string) {
        super(message);
        this.status = status;
    }
}

function writeJson(
    res: import("node:http").ServerResponse<import("node:http").IncomingMessage>,
    statusCode: number,
    body: Record<string, unknown>,
): void {
    res.writeHead(statusCode, {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
    });
    res.end(JSON.stringify(body));
}

const server = createServer(async (req, res) => {
    if (!req.url) {
        writeJson(res, 400, { error: "missing_url" });
        return;
    }

    if (req.method === "GET" && req.url === "/health") {
        writeJson(res, 200, { ok: true });
        return;
    }

    if (req.method === "POST" && req.url === "/token") {
        try {
            const token = await requestTokenWithRetry(3);
            writeJson(res, 200, token);
            return;
        } catch (error) {
            if (error instanceof BrokerHttpError) {
                writeJson(res, error.status, {
                    error: "token_exchange_failed",
                    message: error.message,
                });
                return;
            }

            writeJson(res, 500, {
                error: "internal_error",
                message: "Unexpected token broker failure",
            });
            return;
        }
    }

    writeJson(res, 404, { error: "not_found" });
});

server.listen(PORT, "127.0.0.1", () => {
    console.log(`[broker] listening on http://127.0.0.1:${PORT}`);
});

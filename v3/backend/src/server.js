"use strict";

const http = require("http");
const { URL } = require("url");
const { InMemoryStore } = require("./store");

const PORT = Number(process.env.PORT || 8787);
const HOST = process.env.HOST || "127.0.0.1";
const AGENT_TOKEN = process.env.V3_AGENT_TOKEN || "dev-agent-token";
const MOBILE_TOKEN = process.env.V3_MOBILE_TOKEN || "dev-mobile-token";
const ADMIN_TOKEN = process.env.V3_ADMIN_TOKEN || "dev-admin-token";

const store = new InMemoryStore();

function sendJson(res, code, body) {
  const text = JSON.stringify(body, null, 2);
  res.writeHead(code, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(text)
  });
  res.end(text);
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => {
      chunks.push(chunk);
      if (Buffer.concat(chunks).length > 2 * 1024 * 1024) {
        reject(new Error("Payload too large"));
      }
    });
    req.on("end", () => {
      if (chunks.length === 0) return resolve({});
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8")));
      } catch {
        reject(new Error("Invalid JSON"));
      }
    });
    req.on("error", reject);
  });
}

function authToken(req) {
  const raw = req.headers.authorization || "";
  if (!raw.startsWith("Bearer ")) return "";
  return raw.slice("Bearer ".length).trim();
}

function requireAuth(req, res, kind) {
  const token = authToken(req);
  if (kind === "agent" && token === AGENT_TOKEN) return true;
  if (kind === "mobile" && (token === MOBILE_TOKEN || store.isValidMobileAccessToken(token))) return true;
  if (kind === "admin" && token === ADMIN_TOKEN) return true;
  sendJson(res, 401, { ok: false, error: "UNAUTHORIZED" });
  return false;
}

const server = http.createServer(async (req, res) => {
  const started = Date.now();
  const method = req.method || "GET";
  const url = new URL(req.url || "/", `http://${HOST}:${PORT}`);
  const path = url.pathname;

  try {
    if (method === "GET" && path === "/health") {
      return sendJson(res, 200, {
        ok: true,
        service: "notifier-v3-backend-core",
        uptime_sec: Math.floor(process.uptime()),
        now: new Date().toISOString()
      });
    }

    // Bootstrap helper for local tests
    if (method === "POST" && path === "/v1/admin/pair/code") {
      if (!requireAuth(req, res, "admin")) return;
      const body = await parseBody(req);
      const workspaceId = String(body.workspace_id || "ws_local_dev");
      const code = store.createPairCode(300, workspaceId);
      return sendJson(res, 200, {
        ok: true,
        pair_code: code.code,
        workspace_id: code.workspace_id,
        expires_at: code.expiresAt
      });
    }

    if (method === "POST" && path === "/v1/mobile/pair/start") {
      const body = await parseBody(req);
      const pairCode = String(body.pair_code || "");
      const pair = store.consumePairCode(pairCode);
      if (!pair) {
        return sendJson(res, 400, { ok: false, error: "PAIR_CODE_INVALID_OR_EXPIRED" });
      }
      const session = store.createMobileSession(pair.workspace_id || "ws_local_dev");
      return sendJson(res, 200, {
        ok: true,
        workspace_id: session.workspace_id,
        access_token: session.access_token,
        refresh_token: session.refresh_token,
        access_expires_at: session.access_expires_at,
        refresh_expires_at: session.refresh_expires_at
      });
    }

    if (method === "POST" && path === "/v1/mobile/auth/refresh") {
      const body = await parseBody(req);
      const refreshToken = String(body.refresh_token || "");
      if (!refreshToken) {
        return sendJson(res, 400, { ok: false, error: "refresh_token_required" });
      }
      const session = store.refreshMobileSession(refreshToken);
      if (!session) {
        return sendJson(res, 401, { ok: false, error: "refresh_token_invalid_or_expired" });
      }
      return sendJson(res, 200, { ok: true, ...session });
    }

    if (method === "POST" && path === "/v1/agents/events") {
      if (!requireAuth(req, res, "agent")) return;
      const body = await parseBody(req);
      const event = store.addEvent(body);
      return sendJson(res, 200, { ok: true, event_id: event.event_id });
    }

    if (method === "POST" && path === "/v1/mobile/commands") {
      if (!requireAuth(req, res, "mobile")) return;
      const body = await parseBody(req);
      const cmd = store.addCommand(body);
      return sendJson(res, 200, {
        ok: true,
        command_id: cmd.command_id,
        status: cmd.status
      });
    }

    if (method === "GET" && path === "/v1/agents/commands/pending") {
      if (!requireAuth(req, res, "agent")) return;
      const limit = Number(url.searchParams.get("limit") || "50");
      const items = store.listPendingCommands(limit);
      return sendJson(res, 200, { ok: true, items });
    }

    if (method === "POST" && path === "/v1/agents/actions/ack") {
      if (!requireAuth(req, res, "agent")) return;
      const body = await parseBody(req);
      const commandId = String(body.command_id || "");
      if (!commandId) {
        return sendJson(res, 400, { ok: false, error: "command_id_required" });
      }
      const updated = store.ackCommand(commandId, body.status, body.message);
      if (!updated) return sendJson(res, 404, { ok: false, error: "command_not_found" });
      return sendJson(res, 200, { ok: true, command: updated });
    }

    if (method === "GET" && path === "/v1/mobile/feed") {
      if (!requireAuth(req, res, "mobile")) return;
      const cursor = String(url.searchParams.get("cursor") || "");
      const limit = Number(url.searchParams.get("limit") || "30");
      const feed = store.listEvents({ cursor, limit });
      return sendJson(res, 200, { ok: true, ...feed });
    }

    if (method === "GET" && path === "/v1/debug/state") {
      if (!requireAuth(req, res, "admin")) return;
      return sendJson(res, 200, {
        ok: true,
        events: store.events.length,
        commands: store.commands.length,
        pending_commands: store.commands.filter((c) => c.status === "accepted").length,
        acks: store.acks.length,
        mobile_sessions: store.mobileSessionsByAccess.size
      });
    }

    return sendJson(res, 404, { ok: false, error: "NOT_FOUND", path, method });
  } catch (err) {
    return sendJson(res, 500, {
      ok: false,
      error: "INTERNAL_ERROR",
      message: err && err.message ? err.message : String(err),
      took_ms: Date.now() - started
    });
  }
});

server.listen(PORT, HOST, () => {
  // eslint-disable-next-line no-console
  console.log(`[v3-backend] listening on http://${HOST}:${PORT}`);
});

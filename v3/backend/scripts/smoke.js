"use strict";

const { spawn } = require("child_process");
const path = require("path");

const PORT = 18787;
const BASE_URL = `http://127.0.0.1:${PORT}`;
const TOKENS = {
  admin: "dev-admin-token",
  mobile: "dev-mobile-token",
  agent: "dev-agent-token"
};

function wait(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForHealth(timeoutMs = 15000) {
  const started = Date.now();
  while (Date.now() - started < timeoutMs) {
    try {
      const res = await fetch(`${BASE_URL}/health`);
      if (res.ok) return;
    } catch {
      // Server still warming up.
    }
    await wait(300);
  }
  throw new Error("Server did not become healthy in time.");
}

async function call(pathname, { method = "GET", token = "", body } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  const res = await fetch(`${BASE_URL}${pathname}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} for ${method} ${pathname}: ${JSON.stringify(data)}`);
  }
  return data;
}

async function run() {
  const backendDir = path.resolve(__dirname, "..");
  const server = spawn(process.execPath, ["src/server.js"], {
    cwd: backendDir,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: String(PORT),
      V3_ADMIN_TOKEN: TOKENS.admin,
      V3_MOBILE_TOKEN: TOKENS.mobile,
      V3_AGENT_TOKEN: TOKENS.agent
    },
    stdio: ["ignore", "pipe", "pipe"]
  });

  server.stdout.on("data", (d) => process.stdout.write(`[backend] ${d}`));
  server.stderr.on("data", (d) => process.stderr.write(`[backend:err] ${d}`));

  try {
    await waitForHealth();

    const pair = await call("/v1/admin/pair/code", {
      method: "POST",
      token: TOKENS.admin
    });
    const pairStart = await call("/v1/mobile/pair/start", {
      method: "POST",
      body: { pair_code: pair.pair_code }
    });
    const command = await call("/v1/mobile/commands", {
      method: "POST",
      token: TOKENS.mobile,
      body: {
        target: "codex",
        action: "continue",
        metadata: { client: "smoke-js", ts: new Date().toISOString() }
      }
    });
    const pending = await call("/v1/agents/commands/pending?limit=5", {
      token: TOKENS.agent
    });
    const ack = await call("/v1/agents/actions/ack", {
      method: "POST",
      token: TOKENS.agent,
      body: {
        command_id: command.command_id,
        status: "done",
        message: "smoke-ok"
      }
    });
    const event = await call("/v1/agents/events", {
      method: "POST",
      token: TOKENS.agent,
      body: {
        source: "codex",
        type: "final",
        payload: { text: "Smoke final output" }
      }
    });
    const feed = await call("/v1/mobile/feed?limit=10", {
      token: TOKENS.mobile
    });

    if (!pair.ok || !pairStart.ok || !command.ok || !ack.ok || !event.ok || !feed.ok) {
      throw new Error("Smoke response includes ok=false.");
    }
    if (!Array.isArray(pending.items) || pending.items.length < 1) {
      throw new Error("Expected at least one pending command.");
    }
    if (!Array.isArray(feed.items) || feed.items.length < 1) {
      throw new Error("Expected at least one feed item.");
    }

    console.log(
      JSON.stringify(
        {
          ok: true,
          pair_code: pair.pair_code,
          command_id: command.command_id,
          pending_count: pending.items.length,
          ack_status: ack.command.status,
          event_id: event.event_id,
          feed_count: feed.items.length
        },
        null,
        2
      )
    );
  } finally {
    server.kill("SIGTERM");
    await wait(400);
    if (!server.killed) {
      server.kill("SIGKILL");
    }
  }
}

run().catch((err) => {
  console.error(err.stack || String(err));
  process.exitCode = 1;
});

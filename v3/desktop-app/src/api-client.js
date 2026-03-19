"use strict";

const DEFAULT_API = process.env.V3_API_URL || "http://127.0.0.1:8787";
const DEFAULT_MOBILE_TOKEN = process.env.V3_MOBILE_TOKEN || "dev-mobile-token";

function resolveConfig(payload) {
  return {
    apiUrl: payload && payload.apiUrl ? payload.apiUrl : DEFAULT_API,
    token: payload && payload.token ? payload.token : DEFAULT_MOBILE_TOKEN,
    limit: payload && payload.limit ? payload.limit : 30,
    target: payload && payload.target ? payload.target : "codex",
    action: payload && payload.action ? payload.action : "continue"
  };
}

async function getFeed(payload) {
  const cfg = resolveConfig(payload);
  const url = new URL("/v1/mobile/feed", cfg.apiUrl);
  url.searchParams.set("limit", String(cfg.limit));
  const response = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${cfg.token}` }
  });
  const body = await response.json();
  return {
    ok: response.ok,
    status: response.status,
    body
  };
}

async function sendCommand(payload) {
  const cfg = resolveConfig(payload);
  const response = await fetch(new URL("/v1/mobile/commands", cfg.apiUrl), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${cfg.token}`
    },
    body: JSON.stringify({
      target: cfg.target,
      action: cfg.action,
      metadata: {
        client: "desktop-app",
        ts: new Date().toISOString()
      }
    })
  });
  const body = await response.json();
  return {
    ok: response.ok,
    status: response.status,
    body
  };
}

module.exports = {
  DEFAULT_API,
  DEFAULT_MOBILE_TOKEN,
  getFeed,
  sendCommand
};

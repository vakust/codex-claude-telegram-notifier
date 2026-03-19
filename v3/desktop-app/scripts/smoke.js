"use strict";

const { getFeed, sendCommand, DEFAULT_API, DEFAULT_MOBILE_TOKEN } = require("../src/api-client");

async function run() {
  const cfg = {
    apiUrl: process.env.V3_API_URL || DEFAULT_API,
    token: process.env.V3_MOBILE_TOKEN || DEFAULT_MOBILE_TOKEN,
    agentToken: process.env.V3_AGENT_TOKEN || "dev-agent-token"
  };

  const before = await getFeed({ ...cfg, limit: 20 });
  if (!before.ok) {
    throw new Error(`Feed before failed: HTTP ${before.status} ${JSON.stringify(before.body)}`);
  }

  const command = await sendCommand({
    ...cfg,
    target: "codex",
    action: "continue"
  });
  if (!command.ok) {
    throw new Error(`sendCommand failed: HTTP ${command.status} ${JSON.stringify(command.body)}`);
  }

  const eventResponse = await fetch(new URL("/v1/agents/events", cfg.apiUrl), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${cfg.agentToken}`
    },
    body: JSON.stringify({
      source: "codex",
      type: "final",
      payload: { text: "desktop-smoke-event" }
    })
  });
  const eventBody = await eventResponse.json();
  if (!eventResponse.ok) {
    throw new Error(`agent event failed: HTTP ${eventResponse.status} ${JSON.stringify(eventBody)}`);
  }

  const after = await getFeed({ ...cfg, limit: 20 });
  if (!after.ok) {
    throw new Error(`Feed after failed: HTTP ${after.status} ${JSON.stringify(after.body)}`);
  }

  const beforeCount = Array.isArray(before.body && before.body.items) ? before.body.items.length : 0;
  const afterCount = Array.isArray(after.body && after.body.items) ? after.body.items.length : 0;
  if (afterCount <= beforeCount) {
    throw new Error(`Feed did not grow after agent event: before=${beforeCount}, after=${afterCount}`);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        api: cfg.apiUrl,
        command_id: command.body && command.body.command_id ? command.body.command_id : null,
        event_id: eventBody && eventBody.event_id ? eventBody.event_id : null,
        feed_before: beforeCount,
        feed_after: afterCount
      },
      null,
      2
    )
  );
}

run().catch((err) => {
  console.error(err.stack || String(err));
  process.exitCode = 1;
});

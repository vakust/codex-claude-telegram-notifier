"use strict";

const crypto = require("crypto");

function nowIso() {
  return new Date().toISOString();
}

function nextId(prefix) {
  return `${prefix}_${crypto.randomBytes(6).toString("hex")}`;
}

class InMemoryStore {
  constructor() {
    this.events = [];
    this.commands = [];
    this.acks = [];
    this.pairCodes = new Map();
  }

  createPairCode(ttlSec = 300) {
    const code = `${Math.floor(100 + Math.random() * 900)}-${Math.floor(100 + Math.random() * 900)}`;
    const expiresAt = Date.now() + ttlSec * 1000;
    this.pairCodes.set(code, { code, createdAt: nowIso(), expiresAt });
    return { code, createdAt: nowIso(), expiresAt: new Date(expiresAt).toISOString() };
  }

  consumePairCode(code) {
    const pair = this.pairCodes.get(code);
    if (!pair) return null;
    if (Date.now() > pair.expiresAt) {
      this.pairCodes.delete(code);
      return null;
    }
    this.pairCodes.delete(code);
    return pair;
  }

  addEvent(input) {
    const event = {
      event_id: input.event_id || nextId("evt"),
      event_type: input.event_type || "unknown",
      source: input.source || "controller",
      session_key: input.session_key || "",
      created_at: input.created_at || nowIso(),
      payload: input.payload || {}
    };
    this.events.push(event);
    if (this.events.length > 5000) this.events.shift();
    return event;
  }

  listEvents({ cursor = "", limit = 30 } = {}) {
    const safeLimit = Math.max(1, Math.min(200, Number(limit) || 30));
    let startIdx = this.events.length;
    if (cursor) {
      const idx = this.events.findIndex((e) => e.event_id === cursor);
      if (idx >= 0) startIdx = idx;
    }
    const sliceStart = Math.max(0, startIdx - safeLimit);
    const items = this.events.slice(sliceStart, startIdx);
    const nextCursor = sliceStart > 0 ? this.events[sliceStart].event_id : "";
    return { items, next_cursor: nextCursor };
  }

  addCommand(input) {
    const cmd = {
      command_id: nextId("cmd"),
      target: input.target || "codex",
      action: input.action || "continue",
      metadata: input.metadata || {},
      status: "accepted",
      created_at: nowIso(),
      ack_at: ""
    };
    this.commands.push(cmd);
    if (this.commands.length > 5000) this.commands.shift();
    return cmd;
  }

  listPendingCommands(limit = 50) {
    const safeLimit = Math.max(1, Math.min(200, Number(limit) || 50));
    return this.commands.filter((c) => c.status === "accepted").slice(-safeLimit);
  }

  ackCommand(commandId, status, message) {
    const cmd = this.commands.find((c) => c.command_id === commandId);
    if (!cmd) return null;
    cmd.status = status || "delivered";
    cmd.ack_at = nowIso();
    cmd.ack_message = message || "";
    this.acks.push({
      command_id: commandId,
      status: cmd.status,
      message: cmd.ack_message,
      completed_at: cmd.ack_at
    });
    if (this.acks.length > 5000) this.acks.shift();
    return cmd;
  }
}

module.exports = {
  InMemoryStore
};

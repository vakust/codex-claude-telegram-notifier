/* global notifierApi */

const statusEl = document.getElementById("status");
const healthEl = document.getElementById("healthState");
const apiUrlEl = document.getElementById("apiUrl");
const tokenEl = document.getElementById("token");
const feedOut = document.getElementById("feedOut");
const refreshBtn = document.getElementById("refresh");
const actionButtons = Array.from(document.querySelectorAll(".actions button"));

const STORAGE_KEYS = {
  apiUrl: "notifier_v3_api_url",
  token: "notifier_v3_mobile_token"
};

function setStatus(text) {
  statusEl.textContent = text;
}

function setHealth(state, message) {
  healthEl.classList.remove("ok", "err", "unknown");
  if (state === "ok") {
    healthEl.classList.add("ok");
    healthEl.textContent = `Health: OK (${message || "reachable"})`;
    return;
  }
  if (state === "err") {
    healthEl.classList.add("err");
    healthEl.textContent = `Health: Error (${message || "unreachable"})`;
    return;
  }
  healthEl.classList.add("unknown");
  healthEl.textContent = "Health: Unknown";
}

function readConfigFromInputs() {
  return {
    apiUrl: apiUrlEl.value.trim(),
    token: tokenEl.value.trim()
  };
}

function persistInputState() {
  localStorage.setItem(STORAGE_KEYS.apiUrl, apiUrlEl.value.trim());
  localStorage.setItem(STORAGE_KEYS.token, tokenEl.value.trim());
}

async function loadDefaults() {
  const cfg = await notifierApi.getConfig();
  const savedApi = localStorage.getItem(STORAGE_KEYS.apiUrl);
  const savedToken = localStorage.getItem(STORAGE_KEYS.token);

  apiUrlEl.value = savedApi || cfg.apiUrl || "http://127.0.0.1:8787";
  tokenEl.value = savedToken || cfg.mobileToken || "dev-mobile-token";
  persistInputState();
  setStatus("Defaults loaded.");
}

async function checkHealth() {
  setHealth("unknown");
  const result = await notifierApi.checkHealth(readConfigFromInputs());
  if (result.ok) {
    setHealth("ok", "reachable");
    return true;
  }
  setHealth("err", `HTTP ${result.status}`);
  return false;
}

async function refreshFeed() {
  setStatus("Loading feed...");
  const healthy = await checkHealth();
  if (!healthy) {
    setStatus("Backend health check failed.");
    return;
  }

  const result = await notifierApi.getFeed({
    ...readConfigFromInputs(),
    limit: 20
  });
  if (!result.ok) {
    setStatus(`Feed error: HTTP ${result.status}`);
    feedOut.textContent = JSON.stringify(result.body, null, 2);
    return;
  }
  const items = result.body && result.body.items ? result.body.items : [];
  setStatus(`Feed loaded: ${items.length} item(s).`);
  feedOut.textContent = JSON.stringify(items, null, 2);
}

async function sendAction(target, action) {
  setStatus(`Sending ${target}:${action}...`);
  const result = await notifierApi.sendCommand({
    ...readConfigFromInputs(),
    target,
    action
  });

  if (!result.ok) {
    setStatus(`Command failed: HTTP ${result.status}`);
    return;
  }

  const id = result.body && result.body.command_id ? result.body.command_id : "n/a";
  setStatus(`Accepted: ${id}`);
  await refreshFeed();
}

apiUrlEl.addEventListener("change", persistInputState);
tokenEl.addEventListener("change", persistInputState);
refreshBtn.addEventListener("click", refreshFeed);

for (const btn of actionButtons) {
  btn.addEventListener("click", () => {
    void sendAction(btn.dataset.target, btn.dataset.action);
  });
}

void loadDefaults().then(refreshFeed);

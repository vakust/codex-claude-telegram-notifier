/* global notifierApi */

const statusEl = document.getElementById("status");
const apiUrlEl = document.getElementById("apiUrl");
const tokenEl = document.getElementById("token");
const feedOut = document.getElementById("feedOut");
const refreshBtn = document.getElementById("refresh");
const actionButtons = Array.from(document.querySelectorAll(".actions button"));

function setStatus(text) {
  statusEl.textContent = text;
}

async function loadDefaults() {
  const cfg = await notifierApi.getConfig();
  apiUrlEl.value = cfg.apiUrl || "http://127.0.0.1:8787";
  tokenEl.value = cfg.mobileToken || "dev-mobile-token";
  setStatus("Defaults loaded.");
}

async function refreshFeed() {
  setStatus("Loading feed...");
  const result = await notifierApi.getFeed({
    apiUrl: apiUrlEl.value.trim(),
    token: tokenEl.value.trim(),
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
    apiUrl: apiUrlEl.value.trim(),
    token: tokenEl.value.trim(),
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

refreshBtn.addEventListener("click", refreshFeed);
for (const btn of actionButtons) {
  btn.addEventListener("click", () => {
    void sendAction(btn.dataset.target, btn.dataset.action);
  });
}

void loadDefaults().then(refreshFeed);

"use strict";

const path = require("path");
const { app, BrowserWindow, ipcMain } = require("electron");

const DEFAULT_API = process.env.V3_API_URL || "http://127.0.0.1:8787";
let mainWindow = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1180,
    height: 760,
    minWidth: 980,
    minHeight: 640,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false
    },
    title: "Notifier v3 Control Center"
  });

  mainWindow.loadFile(path.join(__dirname, "renderer", "index.html"));
}

app.whenReady().then(() => {
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});

ipcMain.handle("config:get", async () => {
  return {
    apiUrl: DEFAULT_API,
    mobileToken: process.env.V3_MOBILE_TOKEN || "dev-mobile-token"
  };
});

ipcMain.handle("api:getFeed", async (_event, payload) => {
  const apiUrl = payload && payload.apiUrl ? payload.apiUrl : DEFAULT_API;
  const token = payload && payload.token ? payload.token : process.env.V3_MOBILE_TOKEN || "dev-mobile-token";
  const limit = payload && payload.limit ? payload.limit : 30;

  const url = new URL("/v1/mobile/feed", apiUrl);
  url.searchParams.set("limit", String(limit));

  const response = await fetch(url.toString(), {
    headers: { Authorization: `Bearer ${token}` }
  });
  const body = await response.json();
  return {
    ok: response.ok,
    status: response.status,
    body
  };
});

ipcMain.handle("api:sendCommand", async (_event, payload) => {
  const apiUrl = payload && payload.apiUrl ? payload.apiUrl : DEFAULT_API;
  const token = payload && payload.token ? payload.token : process.env.V3_MOBILE_TOKEN || "dev-mobile-token";
  const target = payload && payload.target ? payload.target : "codex";
  const action = payload && payload.action ? payload.action : "continue";

  const response = await fetch(new URL("/v1/mobile/commands", apiUrl), {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`
    },
    body: JSON.stringify({
      target,
      action,
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
});

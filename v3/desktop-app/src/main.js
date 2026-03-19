"use strict";

const path = require("path");
const { app, BrowserWindow, ipcMain } = require("electron");
const { DEFAULT_API, DEFAULT_MOBILE_TOKEN, getFeed, sendCommand } = require("./api-client");

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
    mobileToken: DEFAULT_MOBILE_TOKEN
  };
});

ipcMain.handle("api:getFeed", async (_event, payload) => getFeed(payload));
ipcMain.handle("api:sendCommand", async (_event, payload) => sendCommand(payload));

"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("notifierApi", {
  getConfig: () => ipcRenderer.invoke("config:get"),
  checkHealth: (payload) => ipcRenderer.invoke("api:checkHealth", payload),
  getFeed: (payload) => ipcRenderer.invoke("api:getFeed", payload),
  sendCommand: (payload) => ipcRenderer.invoke("api:sendCommand", payload)
});

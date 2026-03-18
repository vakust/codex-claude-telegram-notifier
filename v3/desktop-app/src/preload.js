"use strict";

const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("notifierApi", {
  getConfig: () => ipcRenderer.invoke("config:get"),
  getFeed: (payload) => ipcRenderer.invoke("api:getFeed", payload),
  sendCommand: (payload) => ipcRenderer.invoke("api:sendCommand", payload)
});

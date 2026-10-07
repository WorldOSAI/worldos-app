// @ts-check
// Exposes window.WorldOSDesktop to the page. The type contract lives in WorldSims
// (lib/native/desktop.ts); change both together, shell first. Every method resolves to a
// safe value when Steam is unavailable or the page is not worldos.cc — the main process
// re-checks the caller's origin on every call.
const { contextBridge, ipcRenderer } = require("electron");

const info = ipcRenderer.sendSync("desktop:info");

contextBridge.exposeInMainWorld("WorldOSDesktop", {
  shell: "steam",
  version: info.version,
  os: info.os,
  /** new every app start — scope "until the next launch" state to it */
  launchId: info.launchId,
  /** null when Steam isn't running / didn't initialize */
  steam: info.steam,
  openExternal: (/** @type {string} */ url) => ipcRenderer.invoke("desktop:open-external", String(url)),
  toggleFullscreen: () => ipcRenderer.invoke("desktop:toggle-fullscreen"),
  getSteamAuthTicket: () => ipcRenderer.invoke("desktop:steam-auth-ticket"),
  openSteamStore: (/** @type {number | undefined} */ appId) => ipcRenderer.invoke("desktop:steam-open-store", appId ?? null),
  openSteamOverlayUrl: (/** @type {string} */ url) => ipcRenderer.invoke("desktop:steam-open-overlay-url", String(url)),
  isSteamDlcInstalled: (/** @type {number} */ appId) => ipcRenderer.invoke("desktop:steam-dlc-installed", appId),
  unlockSteamAchievement: (/** @type {string} */ name) => ipcRenderer.invoke("desktop:steam-achievement", String(name)),
  onSteamMicroTxn: (/** @type {(payload: unknown) => void} */ callback) => {
    /** @param {unknown} _event @param {unknown} payload */
    const listener = (_event, payload) => callback(payload);
    ipcRenderer.on("desktop:steam-microtxn", listener);
    return () => {
      ipcRenderer.removeListener("desktop:steam-microtxn", listener);
    };
  },
});

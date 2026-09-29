// @ts-check
// Remembers the window's size, position, maximized and fullscreen state between launches.
const { app, screen } = require("electron");
const fs = require("node:fs");
const path = require("node:path");

const DEFAULTS = { width: 1440, height: 900, maximized: false, fullscreen: false };

/** @typedef {{ x?: number, y?: number, width: number, height: number, maximized: boolean, fullscreen: boolean }} WindowState */

function file() {
  return path.join(app.getPath("userData"), "window-state.json");
}

/** @returns {WindowState} */
function load() {
  try {
    const saved = JSON.parse(fs.readFileSync(file(), "utf8"));
    /** @type {WindowState} */
    const state = {
      width: clampSize(saved.width, DEFAULTS.width),
      height: clampSize(saved.height, DEFAULTS.height),
      maximized: saved.maximized === true,
      fullscreen: saved.fullscreen === true,
    };
    // Only restore a position that is still on a connected display (a monitor may
    // have been unplugged since the last session).
    if (Number.isFinite(saved.x) && Number.isFinite(saved.y)) {
      const bounds = { x: saved.x, y: saved.y, width: state.width, height: state.height };
      const area = screen.getDisplayMatching(bounds).workArea;
      const visible =
        bounds.x < area.x + area.width && bounds.x + bounds.width > area.x &&
        bounds.y < area.y + area.height && bounds.y + bounds.height > area.y;
      if (visible) Object.assign(state, { x: saved.x, y: saved.y });
    }
    return state;
  } catch {
    return { ...DEFAULTS };
  }
}

/** @param {import("electron").BrowserWindow} win */
function track(win) {
  let normalBounds = win.getNormalBounds();
  const remember = () => {
    if (!win.isMaximized() && !win.isFullScreen() && !win.isMinimized()) normalBounds = win.getNormalBounds();
  };
  win.on("resize", remember);
  win.on("move", remember);
  win.on("close", () => {
    /** @type {WindowState} */
    const state = {
      ...normalBounds,
      maximized: win.isMaximized(),
      fullscreen: win.isFullScreen(),
    };
    try {
      fs.writeFileSync(file(), JSON.stringify(state));
    } catch (error) {
      console.error("[window-state] save failed:", error);
    }
  });
}

/** @param {unknown} value @param {number} fallback */
function clampSize(value, fallback) {
  return typeof value === "number" && value >= 400 && value <= 10000 ? Math.round(value) : fallback;
}

module.exports = { load, track };

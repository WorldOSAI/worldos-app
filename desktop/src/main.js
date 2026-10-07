// @ts-check
// WorldOS desktop shell (Steam). Loads https://worldos.cc in one window — no copy of the
// web app lives here. The shell adds: Steamworks (overlay, auth tickets, store, DLC,
// achievements), OAuth hand-back from the system browser, window/fullscreen handling,
// and a navigation fence that keeps every other origin in the system browser.
const { app, BrowserWindow, Menu, ipcMain, session, shell } = require("electron");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const { PRODUCTION_ORIGIN, STEAM_APP_ID, PROTOCOL } = require("./config");
const steam = require("./steam");
const windowState = require("./windowState");

const ORIGIN = resolveOrigin();
const APP_ID = resolveSteamAppId();
const DEVTOOLS = !app.isPackaged || process.env.WORLDOS_DESKTOP_DEVTOOLS === "1";
const OFFLINE_PAGE = path.join(__dirname, "offline.html");
// New every process start. Web storage (even sessionStorage) survives restarts in
// Electron, so the page scopes "until the next launch" state to this id.
const LAUNCH_ID = randomUUID();

// Painted before the page's first frame: the site's --background (globals.css), so a
// dark-mode system doesn't flash white on launch.
// The site opens dark in the shell (no saved color mode = dark), so paint the window dark
// before the first frame whatever the OS theme — no white flash on launch.
const backgroundColor = () => "#0d0d0d";

/** @type {BrowserWindow | null} */
let mainWindow = null;
/** Live AI image host rendered straight into pages (see configureSession). */
const POLLINATIONS_ORIGIN = "https://image.pollinations.ai";

/** A deep link that arrived before the window existed (macOS open-url fires early). */
let pendingUrl = /** @type {string | null} */ (null);

if (!app.requestSingleInstanceLock()) {
  // Another instance owns the window; it receives our argv (incl. a deep link on
  // Windows/Linux) through its 'second-instance' event.
  app.quit();
} else {
  start();
}

function start() {
  const launchLink = protocolUrlFromArgv(process.argv);
  const steamState = steam.prepare(APP_ID, {
    packaged: app.isPackaged,
    allowRelaunch: !launchLink,
    overlay: process.env.WORLDOS_DESKTOP_NO_OVERLAY !== "1",
  });
  if (steamState === "relaunching") {
    app.quit();
    return;
  }
  console.log(`[desktop] origin=${ORIGIN} steam=${steamState}${APP_ID ? ` appId=${APP_ID}` : ""}`);

  registerProtocol();
  if (launchLink) pendingUrl = deepLinkTarget(launchLink);

  app.on("open-url", (event, url) => {
    event.preventDefault();
    openDeepLink(url);
  });
  app.on("second-instance", (_event, argv) => {
    const link = protocolUrlFromArgv(argv);
    if (link) openDeepLink(link);
    else focusMainWindow();
  });
  app.on("window-all-closed", () => app.quit());

  if (process.platform === "win32") app.setAppUserModelId("cc.worldos.desktop");

  app.whenReady().then(() => {
    configureSession();
    configureMenu();
    registerIpc();
    steam.onMicroTxnAuthorization((payload) => {
      for (const win of BrowserWindow.getAllWindows()) {
        if (isAppUrl(win.webContents.getURL())) win.webContents.send("desktop:steam-microtxn", payload);
      }
    });
    mainWindow = createMainWindow();
    app.on("activate", () => {
      if (!mainWindow || mainWindow.isDestroyed()) mainWindow = createMainWindow();
    });
  });
}

// ─── Origin / config ────────────────────────────────────────────────────────

function resolveOrigin() {
  const override = process.env.WORLDOS_DESKTOP_ORIGIN;
  // A packaged build ignores the override: store builds only ever load production.
  if (app.isPackaged || !override) return PRODUCTION_ORIGIN;
  return new URL(override).origin;
}

function resolveSteamAppId() {
  const override = Number(process.env.WORLDOS_STEAM_APP_ID);
  if (!app.isPackaged && Number.isInteger(override) && override > 0) return override;
  return STEAM_APP_ID;
}

/** @param {string} url */
function isAppUrl(url) {
  try {
    return new URL(url).origin === ORIGIN;
  } catch {
    return false;
  }
}

/** Hands a URL to the system browser / mail client. Anything else is refused. */
function openOutside(/** @type {string} */ raw) {
  let url;
  try {
    url = new URL(raw);
  } catch {
    return false;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:" && url.protocol !== "mailto:") return false;
  void shell.openExternal(url.toString());
  return true;
}

// ─── Window ─────────────────────────────────────────────────────────────────

function createMainWindow() {
  const state = windowState.load();
  const win = new BrowserWindow({
    ...(state.x !== undefined && state.y !== undefined ? { x: state.x, y: state.y } : {}),
    width: state.width,
    height: state.height,
    minWidth: 960,
    minHeight: 600,
    title: "WorldOS",
    show: false,
    backgroundColor: backgroundColor(),
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webviewTag: false,
      spellcheck: false,
    },
  });
  if (state.maximized) win.maximize();
  if (state.fullscreen || steam.isOnSteamDeck()) win.setFullScreen(true);

  // Show on first paint; don't leave a slow network looking like a failed launch.
  const reveal = () => {
    if (!win.isDestroyed() && !win.isVisible()) win.show();
  };
  win.once("ready-to-show", reveal);
  setTimeout(reveal, 2000);

  windowState.track(win);
  guardContents(win.webContents);
  win.webContents.on("before-input-event", (event, input) => handleShortcut(win, event, input));
  win.on("closed", () => {
    if (mainWindow === win) mainWindow = null;
  });

  const startUrl = pendingUrl ?? new URL("/", ORIGIN).toString();
  pendingUrl = null;
  void win.loadURL(startUrl);
  return win;
}

function focusMainWindow() {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  if (mainWindow.isMinimized()) mainWindow.restore();
  mainWindow.show();
  mainWindow.focus();
}

/**
 * Navigation fence for a page: our origin stays in-app, every other destination
 * (payment pages, Discord, docs…) opens in the system browser.
 * @param {import("electron").WebContents} contents
 */
function guardContents(contents) {
  contents.on("will-navigate", (details) => {
    if (!details.isMainFrame || isAppUrl(details.url)) return;
    details.preventDefault();
    openOutside(details.url);
  });
  contents.on("will-redirect", (details) => {
    if (!details.isMainFrame || isAppUrl(details.url)) return;
    details.preventDefault();
    openOutside(details.url);
  });
  contents.setWindowOpenHandler(({ url }) => {
    if (!isAppUrl(url)) {
      openOutside(url);
      return { action: "deny" };
    }
    // Same-origin popups (a page opened "in a new tab") become in-app windows with
    // the same preload and fence.
    return {
      action: "allow",
      overrideBrowserWindowOptions: { autoHideMenuBar: true, backgroundColor: backgroundColor(), minWidth: 640, minHeight: 480 },
    };
  });
  contents.on("did-create-window", (child) => {
    guardContents(child.webContents);
    child.webContents.on("before-input-event", (event, input) => handleShortcut(child, event, input));
  });
  contents.on("did-fail-load", (_event, errorCode, _description, validatedURL, isMainFrame) => {
    // -3 = ERR_ABORTED (a navigation replaced by another one) — not a failure.
    if (!isMainFrame || errorCode === -3 || !isAppUrl(validatedURL)) return;
    void contents.loadFile(OFFLINE_PAGE, { query: { retry: validatedURL } });
  });
  // Reload a crashed page, but not forever: a page that keeps crashing (e.g. out of
  // memory) falls back to the offline page instead of a reload loop.
  /** @type {number[]} */
  let crashes = [];
  contents.on("render-process-gone", (_event, details) => {
    if (details.reason === "clean-exit" || contents.isDestroyed()) return;
    console.error(`[desktop] renderer gone: ${details.reason}`);
    const now = Date.now();
    crashes = crashes.filter((at) => now - at < 60_000).concat(now);
    if (crashes.length <= 3) {
      contents.reload();
      return;
    }
    const last = contents.getURL();
    void contents.loadFile(OFFLINE_PAGE, { query: { retry: isAppUrl(last) ? last : new URL("/", ORIGIN).toString() } });
  });
}

/**
 * Game-style keys on Windows/Linux (macOS gets them from the app menu roles).
 * @param {BrowserWindow} win
 * @param {import("electron").Event} event
 * @param {import("electron").Input} input
 */
function handleShortcut(win, event, input) {
  if (input.type !== "keyDown" || process.platform === "darwin") return;
  const ctrl = input.control || input.meta;
  const key = input.key;
  const contents = win.webContents;
  let handled = true;
  if (key === "F11") win.setFullScreen(!win.isFullScreen());
  else if (key === "F5" || (ctrl && !input.shift && key.toLowerCase() === "r")) contents.reload();
  else if (ctrl && input.shift && key.toLowerCase() === "r") contents.reloadIgnoringCache();
  else if (ctrl && (key === "=" || key === "+")) contents.setZoomLevel(contents.getZoomLevel() + 0.5);
  else if (ctrl && key === "-") contents.setZoomLevel(contents.getZoomLevel() - 0.5);
  else if (ctrl && key === "0") contents.setZoomLevel(0);
  else if (DEVTOOLS && (key === "F12" || (ctrl && input.shift && key.toLowerCase() === "i"))) contents.toggleDevTools();
  else handled = false;
  if (handled) event.preventDefault();
}

function configureMenu() {
  if (process.platform !== "darwin") {
    Menu.setApplicationMenu(null);
    return;
  }
  // macOS needs a real menu: without the Edit roles, ⌘C / ⌘V stop working.
  Menu.setApplicationMenu(
    Menu.buildFromTemplate([
      { role: "appMenu" },
      { role: "editMenu" },
      {
        label: "View",
        submenu: [
          { role: "reload" },
          { role: "forceReload" },
          ...(DEVTOOLS ? [{ role: /** @type {const} */ ("toggleDevTools") }] : []),
          { type: "separator" },
          { role: "resetZoom" },
          { role: "zoomIn" },
          { role: "zoomOut" },
          { type: "separator" },
          { role: "togglefullscreen" },
        ],
      },
      { role: "windowMenu" },
    ])
  );
}

// ─── Session ────────────────────────────────────────────────────────────────

function configureSession() {
  const ses = session.defaultSession;
  // Plain Chrome UA + our marker: drop the Electron / app-name tokens (some sites
  // degrade for them) and add WorldOSDesktop/<version> so the server can tell the shell apart.
  const ua = ses
    .getUserAgent()
    .replace(/\s?Electron\/\S+/, "")
    .replace(new RegExp(`\\s?${app.getName()}\\/\\S+`), "")
    .concat(` WorldOSDesktop/${app.getVersion()}`);
  ses.setUserAgent(ua);
  app.userAgentFallback = ua;

  // Our origin may use the microphone (hold-to-talk), clipboard writes and fullscreen;
  // everything else is denied.
  const allowed = new Set(["media", "clipboard-sanitized-write", "fullscreen"]);
  ses.setPermissionRequestHandler((_contents, permission, callback, details) => {
    const audioOnly = permission !== "media" || ("mediaTypes" in details && (details.mediaTypes ?? []).every((t) => t === "audio"));
    callback(isAppUrl(details.requestingUrl) && allowed.has(permission) && audioOnly);
  });
  ses.setPermissionCheckHandler((_contents, permission, requestingOrigin) => isAppUrl(requestingOrigin) && allowed.has(permission));

  // The Steam game stays SFW. Some in-world pictures (social posts, dating photos, avatars)
  // are rendered live by image.pollinations.ai straight into the page from model-written
  // prompts, with no server of ours in the path — so the shell turns on Pollinations'
  // strict NSFW filter for every such request (safe=true: an image it flags fails to load
  // instead of rendering). Covers every panel, including URLs already stored in saves.
  ses.webRequest.onBeforeRequest({ urls: [`${POLLINATIONS_ORIGIN}/*`] }, (details, callback) => {
    try {
      const url = new URL(details.url);
      if (url.origin === POLLINATIONS_ORIGIN && url.searchParams.get("safe") !== "true") {
        url.searchParams.set("safe", "true");
        callback({ redirectURL: url.toString() });
        return;
      }
    } catch {
      /* unparsable: let it through unchanged */
    }
    callback({});
  });
}

// ─── Deep links (OAuth hand-back) ───────────────────────────────────────────

function registerProtocol() {
  if (process.defaultApp) {
    // `electron .` in development: register the dev binary + this app's path.
    if (process.argv.length >= 2) app.setAsDefaultProtocolClient(PROTOCOL, process.execPath, [path.resolve(process.argv[1])]);
  } else {
    app.setAsDefaultProtocolClient(PROTOCOL);
  }
}

/** @param {string[]} argv */
function protocolUrlFromArgv(argv) {
  return argv.find((arg) => arg.startsWith(`${PROTOCOL}://`)) ?? null;
}

/** @param {string} raw */
function openDeepLink(raw) {
  // worldos-desktop://focus — Steam's web checkout sends the player's browser back here:
  // just bring the game to the front (the store is already waiting for the order)
  if (/^worldos-desktop:\/\/focus\/?$/i.test(raw)) {
    focusMainWindow();
    return;
  }
  const target = deepLinkTarget(raw);
  if (!target) return;
  if (!mainWindow || mainWindow.isDestroyed()) {
    pendingUrl = target;
    return;
  }
  focusMainWindow();
  void mainWindow.loadURL(target);
}

/**
 * worldos-desktop://auth/callback?code=…&next=… → <origin>/auth/callback?code=…&next=…
 * loaded in THIS app: the PKCE verifier cookie lives in the shell's cookie jar, so only
 * here can the code be exchanged. worldos-desktop://open?path=/worlds/x → that page.
 * @param {string} raw
 */
function deepLinkTarget(raw) {
  let link;
  try {
    link = new URL(raw);
  } catch {
    return null;
  }
  if (link.protocol !== `${PROTOCOL}:`) return null;
  const route = `${link.hostname}${link.pathname}`.replace(/\/+$/, "");
  if (route === "auth/callback") {
    const target = new URL("/auth/callback", ORIGIN);
    for (const key of ["code", "next", "error", "error_code", "error_description"]) {
      const value = link.searchParams.get(key);
      if (value !== null) target.searchParams.set(key, value);
    }
    return target.toString();
  }
  if (route === "open") {
    const pagePath = link.searchParams.get("path") ?? "/";
    if (!pagePath.startsWith("/") || pagePath.startsWith("//") || pagePath.includes("\\")) return null;
    const target = new URL(pagePath, ORIGIN);
    return target.origin === ORIGIN ? target.toString() : null;
  }
  return null;
}

// ─── Bridge (window.WorldOSDesktop) ─────────────────────────────────────────

/**
 * Only our origin's top frame may call the bridge.
 * @param {import("electron").IpcMainEvent | import("electron").IpcMainInvokeEvent} event
 */
function fromApp(event) {
  const frame = event.senderFrame;
  return !!frame && frame === event.sender.mainFrame && isAppUrl(frame.url);
}

/** @param {unknown} value */
function positiveInt(value) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}

function registerIpc() {
  ipcMain.on("desktop:info", (event) => {
    event.returnValue = {
      version: app.getVersion(),
      os: process.platform,
      launchId: LAUNCH_ID,
      steam: fromApp(event) ? steam.info() : null,
    };
  });
  ipcMain.handle("desktop:open-external", (event, url) => fromApp(event) && openOutside(String(url)));
  ipcMain.handle("desktop:toggle-fullscreen", (event) => {
    const win = BrowserWindow.fromWebContents(event.sender);
    if (!fromApp(event) || !win) return false;
    const next = !win.isFullScreen();
    win.setFullScreen(next);
    return next;
  });
  ipcMain.handle("desktop:steam-auth-ticket", (event) => (fromApp(event) ? steam.authTicket() : null));
  ipcMain.handle("desktop:steam-open-store", (event, appId) => {
    const id = appId == null ? APP_ID : positiveInt(appId);
    return fromApp(event) && !!id && steam.openStore(id);
  });
  ipcMain.handle("desktop:steam-open-overlay-url", (event, url) => {
    if (!fromApp(event)) return false;
    try {
      const target = new URL(String(url));
      return target.protocol === "https:" && steam.openOverlayUrl(target.toString());
    } catch {
      return false;
    }
  });
  ipcMain.handle("desktop:steam-dlc-installed", (event, appId) => {
    const id = positiveInt(appId);
    return fromApp(event) && !!id && steam.isDlcInstalled(id);
  });
  ipcMain.handle("desktop:steam-achievement", (event, name) => {
    const id = String(name);
    return fromApp(event) && /^[A-Za-z0-9_]{1,128}$/.test(id) && steam.unlockAchievement(id);
  });
}

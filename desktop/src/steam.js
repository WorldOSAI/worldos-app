// @ts-check
// Steamworks wrapper. Every entry point degrades to an "unavailable" result instead of
// throwing: the web app must keep working when Steam isn't running, the SDK fails to
// initialize, or a single call errors. Purchases and ownership are NEVER decided here —
// the server verifies tickets / transactions with the Steam Web API.
const { STEAM_TICKET_IDENTITY } = require("./config");

/** @typedef {import("steamworks.js").Client} SteamClient */
/** @typedef {Omit<SteamClient, "init" | "runCallbacks">} SteamApi */

/** @type {typeof import("steamworks.js") | null} */
let steamworks = null;
/** @type {SteamApi | null} */
let client = null;
/** @type {{ cancel(): void } | null} */
let lastTicket = null;

/**
 * Must run BEFORE `app.whenReady()`: SteamAPI_Init and the overlay's Chromium switches
 * (in-process GPU, no DirectComposition) only take effect before the GPU process starts.
 *
 * @param {number | null} appId
 * @param {{ packaged: boolean, allowRelaunch: boolean, overlay: boolean }} opts
 * @returns {"relaunching" | "ready" | "unavailable" | "disabled"}
 */
function prepare(appId, opts) {
  if (!appId) return "disabled";
  try {
    steamworks = require("steamworks.js");
  } catch (error) {
    console.error("[steam] native module failed to load:", errorMessage(error));
    return "unavailable";
  }
  // A packaged build started outside Steam (double-clicking the exe) relaunches through
  // Steam so ownership, the overlay and the Steam session are all in place. Skipped when
  // the launch carries a deep link: relaunching would drop it.
  if (opts.packaged && opts.allowRelaunch) {
    try {
      if (steamworks.restartAppIfNecessary(appId)) return "relaunching";
    } catch (error) {
      console.error("[steam] restartAppIfNecessary failed:", errorMessage(error));
    }
  }
  try {
    client = steamworks.init(appId);
  } catch (error) {
    console.warn("[steam] init failed (is Steam running and logged in?):", errorMessage(error));
    client = null;
    return "unavailable";
  }
  if (opts.overlay) {
    try {
      steamworks.electronEnableSteamOverlay();
    } catch (error) {
      console.error("[steam] overlay setup failed:", errorMessage(error));
    }
  }
  return "ready";
}

/** Snapshot handed to the page once at preload time. Plain data only. */
function info() {
  if (!client) return null;
  const api = client;
  const read = (/** @type {() => any} */ fn, /** @type {any} */ fallback) => {
    try {
      return fn();
    } catch {
      return fallback;
    }
  };
  return {
    appId: read(() => api.utils.getAppId(), null),
    steamId: read(() => api.localplayer.getSteamId().steamId64.toString(), null),
    personaName: read(() => api.localplayer.getName(), null),
    language: read(() => api.apps.currentGameLanguage(), null),
    country: read(() => api.localplayer.getIpCountry(), null),
    onSteamDeck: read(() => api.utils.isSteamRunningOnSteamDeck(), false),
  };
}

function isOnSteamDeck() {
  try {
    return !!client?.utils.isSteamRunningOnSteamDeck();
  } catch {
    return false;
  }
}

/**
 * A Steam Web API session ticket, hex-encoded — the server exchanges it via
 * ISteamUserAuth/AuthenticateUserTicket (identity = STEAM_TICKET_IDENTITY).
 * The previous ticket is revoked once a new one is issued.
 */
async function authTicket() {
  if (!client) return null;
  try {
    const ticket = await client.auth.getAuthTicketForWebApi(STEAM_TICKET_IDENTITY);
    if (lastTicket) {
      try {
        lastTicket.cancel();
      } catch {
        /* already invalid */
      }
    }
    lastTicket = ticket;
    return { ticket: ticket.getBytes().toString("hex"), identity: STEAM_TICKET_IDENTITY };
  } catch (error) {
    console.error("[steam] auth ticket failed:", errorMessage(error));
    return null;
  }
}

/** @param {number} appId */
function openStore(appId) {
  if (!client) return false;
  try {
    client.overlay.activateToStore(appId, 0);
    return true;
  } catch (error) {
    console.error("[steam] store overlay failed:", errorMessage(error));
    return false;
  }
}

/** @param {string} url */
function openOverlayUrl(url) {
  if (!client) return false;
  try {
    client.overlay.activateToWebPage(url);
    return true;
  } catch (error) {
    console.error("[steam] web overlay failed:", errorMessage(error));
    return false;
  }
}

/** @param {number} appId */
function isDlcInstalled(appId) {
  if (!client) return false;
  try {
    return client.apps.isDlcInstalled(appId);
  } catch {
    return false;
  }
}

/** @param {string} name */
function unlockAchievement(name) {
  if (!client) return false;
  try {
    const ok = client.achievement.activate(name);
    client.stats.store();
    return ok;
  } catch (error) {
    console.error("[steam] achievement failed:", errorMessage(error));
    return false;
  }
}

/**
 * Forwards MicroTxnAuthorizationResponse (the player approved / declined a purchase in
 * the overlay). Informational only — the server finalizes the order with FinalizeTxn.
 * @param {(payload: { appId: number, orderId: string, authorized: boolean }) => void} handler
 */
function onMicroTxnAuthorization(handler) {
  if (!client || !steamworks) return;
  try {
    client.callback.register(steamworks.SteamCallback.MicroTxnAuthorizationResponse, (value) => {
      handler({ appId: value.app_id, orderId: String(value.order_id), authorized: !!value.authorized });
    });
  } catch (error) {
    console.error("[steam] microtxn callback failed:", errorMessage(error));
  }
}

/** @param {unknown} error */
function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}

module.exports = {
  prepare,
  info,
  isOnSteamDeck,
  authTicket,
  openStore,
  openOverlayUrl,
  isDlcInstalled,
  unlockAchievement,
  onMicroTxnAuthorization,
};

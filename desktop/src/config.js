// @ts-check
// Build-time constants for the desktop shell.

// The ONLY origin a packaged build loads. A dev run may override it with
// WORLDOS_DESKTOP_ORIGIN (e.g. http://localhost:3000); a packaged build ignores the
// override, and scripts/check-release.js refuses to package if this constant changes.
const PRODUCTION_ORIGIN = "https://worldos.cc";

// Steamworks App ID — null until the Steamworks app exists. `npm run steam:upload`
// refuses to ship without it. Dev runs can set WORLDOS_STEAM_APP_ID=480 (Valve's public
// "Spacewar" test app, owned by every Steam account).
/** @type {number | null} */
const STEAM_APP_ID = null;

// URL scheme the system browser uses to hand an OAuth code back to this app
// (https://worldos.cc/auth/desktop → worldos-desktop://auth/callback?code=…).
// Distinct from anything the mobile apps register.
const PROTOCOL = "worldos-desktop";

// Identity string bound into Steam Web API tickets; the server must pass the same value
// to ISteamUserAuth/AuthenticateUserTicket.
const STEAM_TICKET_IDENTITY = "worldos";

module.exports = { PRODUCTION_ORIGIN, STEAM_APP_ID, PROTOCOL, STEAM_TICKET_IDENTITY };

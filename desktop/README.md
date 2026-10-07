# WorldOS Desktop (Steam)

An Electron shell that runs WorldOS as a Steam game. It loads `https://worldos.cc`
in one window: no copy of the web app lives here. It is the desktop sibling of the
Capacitor shell in this repository and follows the same contract
(`../REPOSITORY_CONTRACT.md`):

- **WorldSims** owns the web app, APIs, billing authority and the bridge *types*
  (`lib/native/desktop.ts`).
- **`desktop/`** owns the shell: Electron, Steamworks, packaging and Steam uploads.
  It keeps its own `package.json` and lockfile, separate from the Capacitor ones.

The shell adds:

- **Steamworks** through `steamworks.js`: overlay, Web API auth tickets, store
  overlay, DLC checks, achievements and purchase-approval callbacks.
- **Steam sign-in.** On launch the page (WorldSims `SteamSessionBridge`) gets a Web API
  ticket and posts it to `/api/steam/session`. The server verifies it with Steam and signs
  in to the linked account. A Steam account seen for the first time is asked once: start
  with Steam (one click) or sign in to an existing WorldOS account, which then gets linked.
- **Google sign-in through the system browser** (only for "I have a WorldOS account"). Google blocks OAuth inside
  embedded browsers, so the shell opens the consent screen in the system browser.
  WorldSims' `/auth/desktop` then hands the code back via
  `worldos-desktop://auth/callback`, and the shell finishes the exchange in its own
  window, where the PKCE verifier cookie lives. Email sign-in works in-app as-is.
- **A navigation fence.** `worldos.cc` stays in-app; every other origin (payment
  pages, Discord, docs…) opens in the system browser.
- **Window behavior:** size, position and fullscreen are remembered. F11 toggles
  fullscreen on Windows. Steam Deck starts fullscreen. An offline page with retry
  appears when the site can't be reached.

## Develop

```bash
npm install
npm start                                            # loads https://worldos.cc, Steam off
WORLDOS_STEAM_APP_ID=480 npm start                   # Steam on, via Valve's Spacewar test app
WORLDOS_DESKTOP_ORIGIN=http://localhost:3008 npm start  # a local WorldSims dev server
```

- Launched from a VS Code or agent terminal, `ELECTRON_RUN_AS_NODE=1` may be set
  and Electron starts as plain Node. Prefix the command with `env -u ELECTRON_RUN_AS_NODE`.
- For Google sign-in against a local server, use a port matching the Supabase
  redirect allowlist (`http://localhost:300*`).
- Other environment variables:
  - `WORLDOS_DESKTOP_NO_OVERLAY=1` skips the overlay hooks (in-process GPU).
  - `WORLDOS_DESKTOP_DEVTOOLS=1` enables DevTools in a packaged build.
- A packaged build ignores both overrides. It always loads production and uses
  `STEAM_APP_ID` from `src/config.js`.

## Build

```bash
npm run dist:win   # dist/win-unpacked (x64); also builds on macOS
npm run dist:mac   # dist/mac-universal/WorldOS.app (ad-hoc signed)
```

- Steam ships the unpacked folder, so there is no installer.
- `scripts/check-release.js` fails the build if the production origin constant
  changes, or if a `steam_appid.txt` would ship.
- For a Developer ID-signed Mac build, provide `CSC_LINK`/`CSC_KEY_PASSWORD`.
  `build/entitlements.mac.plist` already allows the Steam overlay's dylib injection.

## Ship to Steam

1. Create the app in Steamworks and put its App ID in `src/config.js` (`STEAM_APP_ID`).
2. In Steamworks, create one depot per OS and set launch options: Windows `WorldOS.exe`,
   macOS `WorldOS.app`.
3. Build, then upload:

```bash
STEAM_BUILDER_USER=<build account> \
STEAM_DEPOT_WINDOWS=<depot id> STEAM_DEPOT_MACOS=<depot id> \
STEAM_SET_LIVE=beta \
npm run steam:upload
```

- `STEAM_SET_LIVE` is optional. The default branch can only be set live from the
  Steamworks site.
- steamcmd prompts for the password and the Steam Guard code on first login.

## Bridge: `window.WorldOSDesktop`

`src/preload.js` defines the bridge. The main process re-checks on every call that
the caller is `worldos.cc`'s top frame.

- **Fields:** `shell`, `version`, `os`, `launchId` (new every app start; web storage
  survives restarts in Electron, so per-launch state keys on it), and `steam` (appId, steamId, personaName,
  language, country, onSteamDeck — or `null` when Steam isn't running).
- **Methods:** `openExternal`, `toggleFullscreen`, `getSteamAuthTicket`,
  `openSteamStore`, `openSteamOverlayUrl`, `isSteamDlcInstalled`,
  `unlockSteamAchievement`, `onSteamMicroTxn`.

Add a method here first and release the shell. Only then deploy web code that
calls it. The web code must degrade when the method is missing.

## Not done yet

- Steam purchases: Zap packs via `ISteamMicroTxn`, finalized by the server. Hide
  the Stripe/PayPal flows inside the shell.
- DLC entitlement: server-side ownership check (`ISteamUser/CheckAppOwnership`),
  which feeds the Freedom Pass.
- Steam mode: SFW-only content and a curated catalog.
- Test on Windows hardware, including the overlay (Shift+Tab) with the in-process GPU.

#!/usr/bin/env bash
# Uploads the built depots to Steam with steamcmd. Build first (npm run dist:win / dist:mac).
#   STEAM_BUILDER_USER   Steamworks build account (steamcmd prompts for the password and
#                        Steam Guard code on first login, then caches the session)
#   STEAMCMD             path to steamcmd (default: steamcmd on PATH)
# Depot IDs / branch: see scripts/steam-vdf.js.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${STEAM_BUILDER_USER:?set STEAM_BUILDER_USER to the Steamworks build account}"

node scripts/check-release.js --require-steam-app-id
node scripts/steam-vdf.js

"${STEAMCMD:-steamcmd}" +login "$STEAM_BUILDER_USER" +run_app_build "$PWD/steam/build/app_build.vdf" +quit

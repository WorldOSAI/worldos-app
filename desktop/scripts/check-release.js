// Release guard: a packaged build must only ever load production, and a Steam upload
// must carry a real App ID. `--require-steam-app-id` is passed by steam-upload.sh.
const fs = require("node:fs");
const path = require("node:path");
const { PRODUCTION_ORIGIN, STEAM_APP_ID } = require("../src/config");

const failures = [];
if (PRODUCTION_ORIGIN !== "https://worldos.cc") {
  failures.push(`PRODUCTION_ORIGIN is ${PRODUCTION_ORIGIN}; release builds must load https://worldos.cc`);
}
if (process.argv.includes("--require-steam-app-id") && !(Number.isInteger(STEAM_APP_ID) && STEAM_APP_ID > 0)) {
  failures.push("STEAM_APP_ID in src/config.js is not set to the Steamworks App ID");
}
// steam_appid.txt lets the exe run outside Steam — it must never ship.
if (fs.existsSync(path.join(__dirname, "..", "src", "steam_appid.txt"))) {
  failures.push("src/steam_appid.txt would be packaged; delete it");
}

if (failures.length) {
  for (const failure of failures) console.error(`✗ ${failure}`);
  process.exit(1);
}
console.log("✓ release config ok");

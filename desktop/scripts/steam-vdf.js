// Writes steam/build/app_build.vdf for steamcmd from the electron-builder output.
//   STEAM_DEPOT_WINDOWS / STEAM_DEPOT_MACOS  depot IDs (a depot is included only when its
//                                           ID is set AND its build output exists)
//   STEAM_BUILD_DESC                        build description (default: version + git sha)
//   STEAM_SET_LIVE                          optional beta branch to set live after upload
const fs = require("node:fs");
const path = require("node:path");
const { execSync } = require("node:child_process");
const { STEAM_APP_ID } = require("../src/config");
const pkg = require("../package.json");

const root = path.join(__dirname, "..");
const outDir = path.join(root, "steam", "build");
const dist = path.join(root, "dist");

const DEPOTS = [
  { env: "STEAM_DEPOT_WINDOWS", dir: "win-unpacked" },
  { env: "STEAM_DEPOT_MACOS", dir: "mac-universal" },
];

const appId = Number(process.env.STEAM_APP_ID || STEAM_APP_ID);
if (!Number.isInteger(appId) || appId <= 0) fail("no Steam App ID (src/config.js STEAM_APP_ID)");

const setLive = (process.env.STEAM_SET_LIVE || "").trim();
// Valve only allows the default branch to go live from the Steamworks site.
if (setLive === "default") fail("STEAM_SET_LIVE=default is not allowed; set the default branch live in Steamworks");

const depots = [];
for (const depot of DEPOTS) {
  const id = process.env[depot.env];
  if (!id) continue;
  if (!/^\d+$/.test(id)) fail(`${depot.env} must be a numeric depot ID`);
  if (!fs.existsSync(path.join(dist, depot.dir))) fail(`${depot.env} is set but dist/${depot.dir} does not exist — build it first`);
  depots.push({ id, dir: depot.dir });
}
if (!depots.length) fail("no depots: set STEAM_DEPOT_WINDOWS and/or STEAM_DEPOT_MACOS");

let sha = "";
try {
  sha = execSync("git rev-parse --short HEAD", { cwd: root, stdio: ["ignore", "pipe", "ignore"] }).toString().trim();
} catch {
  /* not a git checkout */
}
const desc = process.env.STEAM_BUILD_DESC || `WorldOS ${pkg.version}${sha ? ` (${sha})` : ""}`;

const q = (value) => `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
const rel = (target) => path.relative(outDir, target).split(path.sep).join("/");

const lines = [
  `"AppBuild"`,
  `{`,
  `\t"AppID" ${q(appId)}`,
  `\t"Desc" ${q(desc)}`,
  `\t"ContentRoot" ${q(rel(dist))}`,
  `\t"BuildOutput" ${q(rel(path.join(root, "steam", "output")))}`,
  ...(setLive ? [`\t"SetLive" ${q(setLive)}`] : []),
  `\t"Depots"`,
  `\t{`,
  ...depots.flatMap((depot) => [
    `\t\t${q(depot.id)}`,
    `\t\t{`,
    `\t\t\t"FileMapping"`,
    `\t\t\t{`,
    `\t\t\t\t"LocalPath" ${q(`${depot.dir}/*`)}`,
    `\t\t\t\t"DepotPath" "."`,
    `\t\t\t\t"Recursive" "1"`,
    `\t\t\t}`,
    `\t\t\t"FileExclusion" "*.pdb"`,
    `\t\t}`,
  ]),
  `\t}`,
  `}`,
];

fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, "app_build.vdf"), lines.join("\n") + "\n");
console.log(`✓ steam/build/app_build.vdf — app ${appId}, depots ${depots.map((d) => `${d.id}←${d.dir}`).join(", ")}`);

function fail(message) {
  console.error(`✗ ${message}`);
  process.exit(1);
}

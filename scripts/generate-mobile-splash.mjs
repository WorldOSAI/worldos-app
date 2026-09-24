import sharp from "sharp";
import { mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = fileURLToPath(new URL("../", import.meta.url));
const ICON = resolve(ROOT, "assets/branding/logo-icon.png");
const WORDMARK = resolve(ROOT, "assets/branding/logo-wordmark.png");
const LOGO_FRACTION = 0.3;
const WORDMARK_FRACTION = 0.42;
const GAP_FRACTION = 0.055;

const targets = [
  ...["", "-1", "-2"].map((suffix) => [
    `ios/App/App/Assets.xcassets/Splash.imageset/splash-2732x2732${suffix}.png`,
    2732,
    2732,
  ]),
  ["android/app/src/main/res/drawable/splash.png", 480, 320],
  ["android/app/src/main/res/drawable-land-mdpi/splash.png", 480, 320],
  ["android/app/src/main/res/drawable-land-hdpi/splash.png", 800, 480],
  ["android/app/src/main/res/drawable-land-xhdpi/splash.png", 1280, 720],
  ["android/app/src/main/res/drawable-land-xxhdpi/splash.png", 1600, 960],
  ["android/app/src/main/res/drawable-land-xxxhdpi/splash.png", 1920, 1280],
  ["android/app/src/main/res/drawable-port-mdpi/splash.png", 320, 480],
  ["android/app/src/main/res/drawable-port-hdpi/splash.png", 480, 800],
  ["android/app/src/main/res/drawable-port-xhdpi/splash.png", 720, 1280],
  ["android/app/src/main/res/drawable-port-xxhdpi/splash.png", 960, 1600],
  ["android/app/src/main/res/drawable-port-xxxhdpi/splash.png", 1280, 1920],
];

async function renderSplash(output, width, height, transparent = false) {
  const shortSide = Math.min(width, height);
  const logoSize = Math.round(shortSide * LOGO_FRACTION);
  const gap = Math.round(shortSide * GAP_FRACTION);
  const logo = await sharp(ICON).resize(logoSize, logoSize).png().toBuffer();
  const wordmark = await sharp(WORDMARK)
    .resize({ width: Math.round(shortSide * WORDMARK_FRACTION) })
    .png()
    .toBuffer({ resolveWithObject: true });
  const top = Math.round((height - logoSize - gap - wordmark.info.height) / 2);
  const destination = resolve(ROOT, output);
  await mkdir(dirname(destination), { recursive: true });

  await sharp({
    create: {
      width,
      height,
      channels: 4,
      background: transparent ? "#ffffff00" : "#ffffff",
    },
  })
    .composite([{
      input: logo,
      left: Math.round((width - logoSize) / 2),
      top,
    }, {
      input: wordmark.data,
      left: Math.round((width - wordmark.info.width) / 2),
      top: top + logoSize + gap,
    }])
    .png()
    .toFile(destination);
}

for (const [output, width, height] of targets) {
  await renderSplash(output, width, height);
}

// Android's system launch screen uses a separate 288 dp icon canvas. At xxxhdpi
// this is 1152 px; the complete lockup fits inside the central 192 dp safe circle.
await renderSplash("android/app/src/main/res/drawable-xxxhdpi/splash_brand.png", 1152, 1152, true);

console.log(`Generated ${targets.length + 1} splash assets with the stacked WorldOS brand.`);

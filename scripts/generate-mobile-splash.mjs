import sharp from "sharp";

const SOURCE = "public/logo-icon.png";
const LOGO_FRACTION = 0.3;

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

for (const [output, width, height] of targets) {
  const logoSize = Math.round(Math.min(width, height) * LOGO_FRACTION);
  const logo = await sharp(SOURCE).resize(logoSize, logoSize).png().toBuffer();

  await sharp({
    create: { width, height, channels: 3, background: "#ffffff" },
  })
    .composite([{
      input: logo,
      left: Math.round((width - logoSize) / 2),
      top: Math.round((height - logoSize) / 2),
    }])
    .png()
    .toFile(output);
}

console.log(`Generated ${targets.length} splash assets with a ${LOGO_FRACTION * 100}% logo.`);

# WorldOS App

Native iOS and Android shell for WorldOS, built with Capacitor.

This repository owns native projects, native configuration, native dependencies,
signing/build automation, and App Store/Google Play releases. The installed shell
loads the deployed WorldOS Web application from `https://worldos.cc`; it does not own
or copy the Next.js application.

Read [REPOSITORY_CONTRACT.md](./REPOSITORY_CONTRACT.md) before adding files or
changing a plugin. The Web-side architecture and compatibility policy live in
`WorldOSAI/WorldSims/docs/worldos-app-architecture.md`.

## Local verification

```bash
npm ci
npm run mobile:sync
cd android && ./gradlew assembleDebug
```

On macOS, also build the `App` scheme for an iOS Simulator. Release sync must use:

```bash
npm run mobile:sync:release
```

That command rejects any release origin other than `https://worldos.cc`.

## Splash screen branding

Native-owned source images live in `assets/branding/`: the WorldOS icon and the
original website wordmark, preserving its lettering and colors. The launch screen
centers the icon above the wordmark on white. Replace these PNGs and run:

```bash
npm run mobile:splash
```

The generator updates iOS `Splash.imageset`, Android fallback splash images, and
the transparent Android system launch icon. Its layout constants control icon
size, wordmark width, and spacing. Keep the system icon's complete artwork inside
the central 192 dp circle of its 288 dp canvas to avoid Android masking.
Commit the source images and generated native resources, then rebuild the App;
Web deployments do not update installed launch screens.

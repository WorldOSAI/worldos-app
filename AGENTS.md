# WorldOS App — Agent Notes

## Required reading

- Before changing this repository, read `REPOSITORY_CONTRACT.md` completely.
- For cross-repository work, also read
  `WorldOSAI/WorldSims/docs/worldos-app-architecture.md`.

## Repository boundary

- This repository owns `android/**`, `ios/**`, `capacitor.config.ts`, native
  dependencies/configuration, native assets/code, signing, builds, and store releases.
- It also owns `desktop/**`, the Electron shell released on Steam. `desktop/` has its
  own `package.json` and lockfile. Never add Electron/Steam packages to the root
  manifest or Capacitor packages to `desktop/`. Read `desktop/README.md` before
  changing it.
- WorldSims owns Next.js/Web/API/Supabase, `lib/native/**`, `window.WorldOSNative`,
  `window.WorldOSDesktop` types, and server-side billing/reward authority. Do not copy
  or submodule WorldSims.
- A clean clone must install, sync, and build both platforms without WorldSims.
- Production/release builds must fail unless the server URL is exactly
  `https://worldos.cc`; local/Preview URLs are development-only.
- Add native capabilities App-first, then deploy their WorldSims callers. Native
  failures must not make the WebView unusable. Client purchase/reward results are
  never server authority.
- Never commit credentials, signing material, service configuration secrets, native
  build output, generated Capacitor files, copied Web assets, or IDE user state.
- During migration, keep the WorldSims native copy until this repository has a
  committed baseline that passes clean install, sync, Android build, and iOS build.

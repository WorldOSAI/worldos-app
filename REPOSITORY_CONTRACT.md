# WorldOS App repository contract

Status: repository ownership contract
Web counterpart: `WorldOSAI/WorldSims/docs/worldos-app-architecture.md`

## Responsibility

This repository builds and releases the `cc.worldos.app` Capacitor shell for iOS and
Android. The shell normally loads `https://worldos.cc`.

It owns:

- `android/**`, `ios/**`, and `capacitor.config.ts`;
- its native package manifest and lockfile;
- native plugins and custom native code;
- manifests, plist files, entitlements, icons, launch/offline assets, and native
  version/build numbers;
- signing, Android/iOS builds, and store releases; and
- native configuration supplied through ignored local files or protected CI.

It does not own Next.js, React UI, APIs, Supabase, server billing/rewards,
`lib/native/**`, or `window.WorldOSNative`. Those remain in WorldSims. Do not copy,
vendor, or submodule the WorldSims source tree.

## Minimal integration rules

- A clean clone must install, run Capacitor sync, and build both platforms without a
  WorldSims checkout.
- New native plugins or methods release here before WorldSims deploys callers that
  require them.
- Native methods reject predictably when unavailable; they must not leave the WebView
  unusable.
- Existing native methods are not removed or changed until installed callers no
  longer need the old behavior.
- Client purchase, subscription, and reward results are never server authority.
- Capacitor/plugin versions remain compatible with JavaScript packages used by
  WorldSims; the repositories keep independent lockfiles.

No custom handshake protocol, capability registry, adoption service, or generated
cross-repository SDK is required for the repository split.

## Production URL

A production/release build must fail unless its server URL is exactly
`https://worldos.cc`. Preview and local URLs are allowed only in development builds
and must never enter store artifacts.

## Secrets and generated files

Never commit certificates, provisioning profiles, keystores, private keys, tokens,
`google-services.json`, `GoogleService-Info.plist`, build output, DerivedData, Xcode
user state, generated Capacitor configuration, copied Web assets, or generated
Cordova plugin projects.

Shared Xcode schemes and StoreKit test configuration may be committed when required
for reproducible builds/tests after confirming they contain no user-specific or
sensitive data.

## Initial migration

1. Start from an updated WorldSims mobile branch with known-good Web, Android, and iOS
   builds.
2. Inventory tracked and ignored native inputs, including the Xcode shared scheme and
   `WorldOS.storekit`.
3. Copy native-owned files and create an independent package, lockfile, ignore rules,
   and production-origin guard.
4. Verify clean installation, Capacitor sync, Android build, and iOS build from a
   clean clone.
5. Commit this verified baseline before WorldSims deletes its native project copy.
6. Keep the pre-split WorldSims commit available for rollback history.

The split is complete when this repository builds independently and WorldSims builds
without the native toolchain.

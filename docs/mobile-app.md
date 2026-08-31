# WorldOS mobile app

The first mobile release is a Capacitor 8 native shell around the deployed WorldOS
Next.js application. Next.js, Supabase, AI routes, and webhooks remain deployed on
Vercel. Native-only features are loaded lazily through `lib/native/client.ts`.

## Local workflow

Requirements:

- Node.js and the existing npm dependencies
- Android Studio with the Android SDK/JDK
- Xcode 16+ on macOS for iOS

```bash
npm install
CAPACITOR_SERVER_URL=https://worldos.cc npm run mobile:sync
npm run mobile:android
npm run mobile:ios
```

For local-device testing, use an HTTPS tunnel URL as `CAPACITOR_SERVER_URL`. Cleartext
HTTP is enabled only when the configured URL starts with `http://`.

The bundle identifiers currently are:

- iOS: `cc.worldos.app`
- Android: `cc.worldos.app`
- Custom deep-link scheme: `worldos://`
- Universal/App Link domain: `https://worldos.cc`

Before the App/Universal Link can be verified, deploy the corresponding
`apple-app-site-association` and `assetlinks.json` files with the final Apple Team ID
and Android signing certificate fingerprint.

## Advertising

`RewardedAdCard` automatically uses native AdMob inside the app and Google Publisher
Tag on the web. The native projects intentionally contain Google's sample AdMob App
IDs, and the JS bridge falls back to Google's sample rewarded unit IDs. Replace the
App IDs in:

- `android/app/src/main/res/values/strings.xml`
- `ios/App/App/Info.plist`

Set `NEXT_PUBLIC_ADMOB_IOS_REWARDED_ID` and
`NEXT_PUBLIC_ADMOB_ANDROID_REWARDED_ID`, then set
`NEXT_PUBLIC_ADMOB_TEST_MODE=0` only for a signed release build.

The bridge attaches the WorldOS reward session as AdMob SSV custom data. The current
first-build fallback still claims through the authenticated WorldOS reward endpoint
after the native SDK returns a reward. Production rollout must add an AdMob
server-side-verification callback and make that callback authoritative before enabling
valuable rewards for all users.

## Push notifications

Set `NEXT_PUBLIC_ONESIGNAL_APP_ID` to enable OneSignal. The bridge logs in to OneSignal
with the authenticated Supabase user UUID and exposes an explicit permission button in
Account → Preferences. Notification payloads may include an `additionalData.url` value
under `worldos://`, `https://worldos.cc`, or a WorldOS subdomain; other targets are
ignored by the in-app navigator.

OneSignal still requires APNs credentials for the iOS app and an FCM project for the
Android app. Add `android/app/google-services.json` locally; it is ignored by Git and
must never be committed. Enable Push Notifications and the existing entitlements in
the Apple Developer/Xcode signing profile.

The existing `notifications` database remains the in-product inbox. Connecting every
notification-row insert to OneSignal delivery is a separate server/database rollout;
it requires the repository-mandated Supabase workflow and is not performed by the
native client.

## TikTok attribution

The app uses the official AppsFlyer Capacitor SDK. Configure
`NEXT_PUBLIC_APPSFLYER_DEV_KEY` and `NEXT_PUBLIC_APPSFLYER_IOS_APP_ID`, then connect
TikTok for Business in AppsFlyer Integrated Partners. Existing WorldOS conversion calls
are mirrored to standard AppsFlyer event names while the browser continues to use the
TikTok Pixel and Events API. Purchase server events remain the source of truth.

Complete SKAdNetwork IDs, ATT consent copy, TikTok Advanced Matching, and deferred
deep links in the AppsFlyer/TikTok dashboards before running paid acquisition.

## Native purchases

The app uses RevenueCat over StoreKit and Google Play Billing. Web users continue to
use Stripe. Configure the two public RevenueCat SDK keys and create packages whose
product IDs follow `cc.worldos.<sku>` (configurable prefix) or whose RevenueCat package
identifier equals the WorldOS SKU.

Examples:

- `cc.worldos.small`
- `cc.worldos.voyager`
- `cc.worldos.freedom`

The pricing UI invokes RevenueCat only on native platforms and does not open Stripe.
Account → Preferences provides Restore Purchases.

Configure RevenueCat to POST to `/api/billing/revenuecat/webhook` with the exact
`REVENUECAT_WEBHOOK_TOKEN` value in its Authorization header. Purchases, renewals,
cancellations, expirations, and consumable Zap grants are mirrored into WorldOS; Zap
credits are idempotent by store transaction/event ID. The client purchase result is never
trusted to grant currency.

### iOS subscription verification (2026-08-27)

- App Store Connect contains `cc.worldos.explorer`, `cc.worldos.voyager`, and
  `cc.worldos.legend` in the `WorldOS Zap Plans` group, ordered highest to lowest.
  `cc.worldos.freedom` is in the separate `WorldOS Freedom Pass` group, matching the
  backend's independent `zap` and `freedom` subscription kinds.
- All inspected products are monthly and in **Ready to Submit** state. Explorer is
  available in every country or region, but its App Store localization and review
  screenshot are still missing; complete the same review metadata check for all four
  products before submission.
- `npx cap sync ios`, TypeScript, focused ESLint, and an unsigned iOS Simulator Debug
  build pass. The build resolves RevenueCat Purchases iOS 5.84.0 through the Capacitor
  plugin.
- Real Offerings, localized StoreKit prices, purchase, restore, renewal, expiration,
  and backend webhook mirroring remain blocked until the webhook token is configured
  outside git and the physical iPhone is online. Use only an App Store Sandbox Tester
  for those checks.
- RevenueCat's App Store credentials are valid. The four iOS products are imported and
  mapped one-to-one to the `explorer`, `freedom`, `voyager`, and `legend` entitlements.
  The default `current` offering contains custom packages with the same four identifiers.
  The iOS Public SDK Key is configured only in the local ignored environment file; it
  must also be added to the deployment environment before the production app can load it.

## Release checklist

1. Replace sample AdMob App IDs and configure production rewarded units.
2. Add AdMob SSV verification before enabling real Zap rewards.
3. Configure APNs, FCM, OneSignal, and notification delivery from the backend.
4. Configure AppsFlyer + TikTok and all required SKAdNetwork identifiers.
5. Create Apple/Google products and enable the verified RevenueCat webhook.
6. Add App Store/Play privacy disclosures, ATT/UMP consent, icons, screenshots, and
   signing profiles.
7. Replace the remote-server first release with a bundled mobile frontend over time;
   Capacitor documents `server.url` as a live-reload option rather than a production
   architecture.

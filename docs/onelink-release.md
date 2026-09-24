# OneLink release contract

This shell accepts the production branded host **go.worldos.cc** on iOS and
Android. It preserves **worldos.cc** links and the **worldos://** URL scheme.
No unregistered AppsFlyer `*.onelink.me` subdomain is assumed or wildcarded.

## What ships in this binary

- iOS Associated Domains includes `applinks:go.worldos.cc`.
- Android has a separate auto-verified HTTPS filter for `go.worldos.cc`.
- The iOS scene proxy is registered before the window is presented so its
  cold-start URL replay is armed before plugins/the controller appear.
- AppsFlyer Capacitor **6.18.0** is already a native dependency on both platforms.
  Capacitor **8.5.0** forwards URLs to that plugin and the App plugin. The SDK
  caches early iOS URL notifications until Web initialization registers listeners.

The Web-owned bridge must call `setOneLinkCustomDomain({domains:
["go.worldos.cc"]})` before `initSDK`, register UDL and conversion listeners,
and treat OneLink short paths as SDK inputs rather than WebView routes. Version
6.18.0's iOS domain setter does not resolve its declared JavaScript promise;
enqueue it without awaiting it. Implementation and acceptance tests live in
WorldSims `docs/onelink-deep-links.md` / `lib/native/**`.

## Agreed link format

```
https://go.worldos.cc/<templateId>/<linkId>
deep_link_value = world
deep_link_sub1  = <world slug>
af_dp          = worldos://worlds/<same slug>
```

Template/link IDs are assigned in AppsFlyer. New worlds, ad creatives and link
paths do not need an App update. A new hostname does. Keep the production
WebView origin exactly `https://worldos.cc`; the branded domain must NOT replace
`server.url` or become a second app content origin.

## Activation after the App release

1. Create the AppsFlyer OneLink template for both store apps. Use the actual App
   Store ID, `cc.worldos.app`, signed Apple application ID prefix and Android
   **Play App Signing** SHA-256 fingerprint (plus a direct APK signer if used).
2. Enable Branded Domains in the applicable AppsFlyer plan; map `go.worldos.cc`
   using the exact CNAME AppsFlyer supplies. AppsFlyer hosts its AASA/assetlinks
   association files. Do not send this domain to Vercel or invent a CNAME target.
3. Finish DNS/TLS/domain verification and confirm both association URLs respond
   without authentication or redirects. OS/CDN association caches can take time
   to update; test a clean install after the domain goes live too.
4. Deploy the companion WorldSims Web changes and its SDK configuration. Complete
   TikTok Advanced SRN association and configure supported ad destination fields.
5. Test a real generated branded link and a real supported ad-to-store install
   on physical devices before starting paid acquisition.

The Web implementation gates AppsFlyer on iOS ATT authorization. Ordinary
worldos.cc / worldos:// navigation does not require ATT. SDK-dependent short
links/deferred matches are not guaranteed without authorization. TikTok also
documents campaign eligibility restrictions, including iOS 14.5+ dedicated
campaigns; shipping SDK code does not bypass those restrictions.

## Build versus end-to-end verification

`npm run mobile:sync:release`, Android `assembleDebug`, and an unsigned iOS
Simulator build validate native integration. They do not verify release signing,
provisioning profiles, live domain association, or ad attribution. Confirm the
signed archive carries `applinks:go.worldos.cc` before submission. The Apple
signing team in the current project is `Q57YZF24RD`; verify the actual signed
application-identifier prefix instead of assuming they can never differ.

Device checks: installed app foreground/background/terminated; fresh store
install; login or consent in progress; offline/slow callback; duplicate callback;
ordinary next launch; unavailable world. The destination must remain a world
detail page subject to existing server access checks, never an automatic game
start, purchase, or permission bypass.

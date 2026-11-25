# Apple AdServices bridge

`AppleAdsAttribution.getToken()` returns `{ token: string }` from Apple's
`AAAttribution.attributionToken()`. The call runs off the main thread and resolves
or rejects on the main queue. Failure uses the generic
`APPLE_ATTRIBUTION_UNAVAILABLE` code; tokens are never logged or persisted.

WorldOS Web owns the caller, posts the token to its first-party server, and joins
the verified Apple response to existing account/gameplay/payment facts. This
native plugin does not call RevenueCat, AppsFlyer, collect IDFA, prompt ATT or use
the reinstall-proof DeviceIdentity identifier. It has no new configuration keys.

Release this native capability before enabling/deploying its Web caller. Old
binaries have no plugin, so Web must detect absence and skip collection safely.
No version number, signing setting or store release is changed by this patch.

Reference: [Apple AdServices token API](https://developer.apple.com/documentation/adservices/aaattribution/attributiontoken())

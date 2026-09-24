# Rewarded ad revenue patch

WorldSims PR #633 consumes AdMob paid events to calculate App-only dynamic rewards.
AdMob 8.1.0's iOS rewarded and rewarded-interstitial implementations truncate
`adValue.value` (currency units) directly to an integer while naming it `valueMicros`.
A $0.005 impression therefore reports zero. The postinstall patch multiplies by
1,000,000 before truncation; Android already reports micros correctly.

Both native plugins expose one optional `getRewardedRevenueVersion` promise,
returning `{ version: 1 }`. Web code probes it before requesting a dynamic reward
session. Older binaries reject the method and keep the original fixed rewards.
This method does not grant rewards. Google SSV remains the eligibility authority;
revenue is client-reported, capped and settled by the WorldSims backend.

`npm ci` applies the patch reproducibly; `node scripts/test-admob-revenue.mjs`
checks idempotence and (on macOS) decimal conversion using Foundation. A dependency
version/source mismatch fails installation so a future upgrade cannot silently
remove the fix. No manually edited node_modules needs to be committed.

Release this native change before enabling `ADMOB_DYNAMIC_REWARDS_ENABLED=1` on
WorldSims. Confirm AdMob impression-level revenue is enabled and verify both ad
formats on real iOS/Android devices before activating the server switch. Native
builds and mock tests alone cannot validate live Google income/SSV delivery.

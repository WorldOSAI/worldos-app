import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const root = new URL('../node_modules/@capacitor-community/admob/', import.meta.url);
const paths = ['ios/Sources/AdMobPlugin/Rewarded/AdRewardExecutor.swift','ios/Sources/AdMobPlugin/RewardedInterstitial/AdRewardInterstitialExecutor.swift','ios/Sources/AdMobPlugin/AdMobPlugin.swift','android/src/main/java/com/getcapacitor/community/admob/AdMob.java','android/src/main/java/com/getcapacitor/community/admob/rewardedinterstitial/RewardedInterstitialAdCallbackAndListeners.kt'];
const before = paths.map(p => readFileSync(new URL(p,root),'utf8'));
execFileSync(process.execPath,[new URL('./patch-admob-revenue.mjs',import.meta.url).pathname]);
assert.deepEqual(paths.map(p => readFileSync(new URL(p,root),'utf8')),before,'patch must be idempotent after npm ci');
if (process.platform === 'darwin') {
  execFileSync('swift',['-e',`import Foundation
    for (dollars, micros) in [("0.000001", Int64(1)), ("0.005", 5000), ("0.10", 100000), ("0", 0)] {
      let value = NSDecimalNumber(string: dollars)
      assert(value.multiplying(by: NSDecimalNumber(value: 1_000_000)).int64Value == micros)
    }
  `],{timeout:60000});
}
console.log('AdMob patch: idempotence and decimal currency-to-micros checks passed');

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const root = new URL('../node_modules/@capacitor-community/admob/', import.meta.url);
const version = JSON.parse(readFileSync(new URL('package.json', root), 'utf8')).version;
if (version !== '8.1.0') throw new Error(`Review AdMob revenue patch for ${version}`);
function patch(path, before, after) {
  const file = fileURLToPath(new URL(path, root));
  const source = readFileSync(file, 'utf8');
  if (source.includes(after)) return;
  if (source.split(before).length !== 2) throw new Error(`Unexpected AdMob source: ${path}`);
  writeFileSync(file, source.replace(before, after));
}
for (const name of ['Rewarded/AdRewardExecutor', 'RewardedInterstitial/AdRewardInterstitialExecutor']) {
  patch(`ios/Sources/AdMobPlugin/${name}.swift`,
    '"valueMicros": adValue.value.int64Value',
    '"valueMicros": adValue.value.multiplying(by: NSDecimalNumber(value: 1_000_000)).int64Value');
}
// Tiny feature probe: old binaries reject this method and keep fixed rewards.
patch('ios/Sources/AdMobPlugin/AdMobPlugin.swift',
  'public let pluginMethods: [CAPPluginMethod] = [',
  'public let pluginMethods: [CAPPluginMethod] = [\n        CAPPluginMethod(name: "getRewardedRevenueVersion", returnType: CAPPluginReturnPromise),');
patch('ios/Sources/AdMobPlugin/AdMobPlugin.swift',
  '    private let appOpenAdPlugin = AppOpenAdPlugin()',
  '    @objc func getRewardedRevenueVersion(_ call: CAPPluginCall) {\n        call.resolve(["version": 1])\n    }\n\n    private let appOpenAdPlugin = AppOpenAdPlugin()');
patch('android/src/main/java/com/getcapacitor/community/admob/AdMob.java',
  'public class AdMob extends Plugin {',
  'public class AdMob extends Plugin {\n    @PluginMethod\n    public void getRewardedRevenueVersion(PluginCall call) {\n        JSObject result = new JSObject();\n        result.put("version", 1);\n        call.resolve(result);\n    }');
console.log('AdMob 8.1.0: rewarded revenue micros and version probe patched');

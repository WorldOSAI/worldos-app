// AGP 9 rejects getDefaultProguardFile('proguard-android.txt') at configuration time.
// These two plugins still name it in their own library build files. Neither minifies
// its library (minifyEnabled false), so the file they name is never used: the app's
// R8 run takes its rules from android/app. Swap in the supported default so the
// project configures; drop an entry once its plugin ships the fix.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const plugins = [
  { name: 'appsflyer-capacitor-plugin', version: '6.18.0' },
  { name: '@capacitor-community/admob', version: '8.1.0' },
];
const before = "getDefaultProguardFile('proguard-android.txt')";
const after = "getDefaultProguardFile('proguard-android-optimize.txt')";

for (const { name, version } of plugins) {
  const root = new URL(`../node_modules/${name}/`, import.meta.url);
  const installed = JSON.parse(readFileSync(new URL('package.json', root), 'utf8')).version;
  if (installed !== version) throw new Error(`Review the AGP 9 build patch for ${name} ${installed}`);
  const file = fileURLToPath(new URL('android/build.gradle', root));
  const source = readFileSync(file, 'utf8');
  if (!/minifyEnabled\s*=?\s*false/.test(source)) throw new Error(`${name} now minifies its library: review the AGP 9 build patch`);
  if (source.includes(before)) writeFileSync(file, source.split(before).join(after));
  else if (!source.includes(after)) throw new Error(`Unexpected ${name} android/build.gradle`);
}
console.log('AGP 9: plugin library build files use the supported default ProGuard file');

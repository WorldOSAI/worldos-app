import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const root = new URL('../', import.meta.url);
const source = fs.readFileSync(new URL('mobile-dist/recovery.js', root), 'utf8');
for (const file of ['index.html', 'offline.html']) {
  const html = fs.readFileSync(new URL(`mobile-dist/${file}`, root), 'utf8');
  assert.match(html, /<script src="recovery\.js"><\/script>/);
  assert.doesNotMatch(html, /getServerUrl|\bfetch\(/);
}

function fixture(target, throws = false) {
  const windowEvents = new Map(), documentEvents = new Map(), buttonEvents = new Map();
  const timers = new Map(), navigations = [];
  let timerId = 0;
  const button = { textContent: 'Try again', disabled: false, addEventListener: (name, fn) => buttonEvents.set(name, fn) };
  const document = {
    visibilityState: 'visible', getElementById: id => id === 'retry' ? button : null,
    addEventListener: (name, fn) => documentEvents.set(name, fn),
  };
  vm.runInNewContext(source, {
    URL, document, Date: { now: () => 12345 },
    window: {
      WorldOSAppServerURL: target,
      Capacitor: { getServerUrl() { throw Error('the asset origin must never be the retry target'); } },
      addEventListener: (name, fn) => windowEvents.set(name, fn),
    },
    location: { replace(url) { if (throws) throw Error('navigation failed'); navigations.push(new URL(url)); } },
    fetch() { throw Error('recovery must not wait for a cross-origin preflight'); },
    setTimeout(fn, delay) { const id = ++timerId; timers.set(id, { fn, delay }); return id; },
    clearTimeout: id => timers.delete(id),
  });
  return {
    button, document, navigations, timers,
    click: () => buttonEvents.get('click')(),
    event: name => windowEvents.get(name)(),
    visible(value) { document.visibilityState = value; documentEvents.get('visibilitychange')(); },
    expire() { for (const { fn, delay } of [...timers.values()]) { assert.equal(delay, 10000); fn(); } },
  };
}

// This is the regression: even with a Capacitor asset-origin getter, retry
// navigates to HTTPS WorldOS instead of capacitor://localhost/index.html.
for (const target of [undefined, 'capacitor://localhost', 'javascript:alert(1)', 'https://user:password@example.com', 'invalid']) {
  const h = fixture(target); h.click();
  assert.equal(h.navigations[0].origin, 'https://worldos.cc');
  assert.equal(h.navigations[0].searchParams.get('native-retry'), '12345');
  assert.equal(h.button.disabled, true);
  h.click(); assert.equal(h.navigations.length, 1, 'double clicks do not create competing navigations');
  h.expire(); assert.equal(h.button.disabled, false); assert.equal(h.button.textContent, 'Try again');
  h.click(); assert.equal(h.navigations.length, 2, 'a stalled request never requires killing the app');
  h.event('pagehide'); assert.equal(h.timers.size, 0);
}
{
  const h = fixture('http://127.0.0.1:3000/preview?existing=1'); h.click();
  assert.equal(h.navigations[0].origin, 'http://127.0.0.1:3000');
  assert.equal(h.navigations[0].pathname, '/preview');
  assert.equal(h.navigations[0].searchParams.get('existing'), '1');
}
{
  const h = fixture(); h.click();
  h.visible('hidden'); assert.equal(h.navigations.length, 1);
  h.visible('visible'); assert.equal(h.navigations.length, 2, 'returning from VPN settings retries immediately');
  h.event('online'); assert.equal(h.navigations.length, 3, 'a restored connection retries the remote service');
  h.event('pagehide'); assert.equal(h.timers.size, 0);
  h.event('pageshow'); assert.equal(h.button.disabled, false, 'a cached error page remains usable');
}
{
  const h = fixture(undefined, true); h.click();
  assert.equal(h.button.disabled, false); assert.equal(h.timers.size, 0);
}
console.log('Offline recovery: remote URL, local-origin regression, native dev URL, no preflight, timeout, VPN/online recovery and teardown passed');

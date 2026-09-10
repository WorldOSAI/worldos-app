# iOS tracking authorization

The native `TrackingAuthorization` Capacitor plugin requests ATT once per bridge
lifetime when the app first becomes active with its WebView presented. iOS controls
whether a prompt appears; an existing decision or system restriction does not
produce another prompt. The system status is always the source of truth.

## Web integration (owned by WorldSims)

```ts
import { registerPlugin, type PluginListenerHandle } from '@capacitor/core';

type TrackingState = {
  status: 'authorized' | 'denied' | 'restricted' | 'notDetermined' | 'unknown';
  canTrack: boolean;
};

const tracking = registerPlugin<{
  getStatus(): Promise<TrackingState>;
  requestAuthorization(): Promise<TrackingState>;
  addListener(
    event: 'statusChanged',
    listener: (state: TrackingState) => void,
  ): Promise<PluginListenerHandle>;
}>('TrackingAuthorization');
```

- This plugin is iOS-only. Check the platform and plugin availability before use;
  older installed shells do not implement it. Missing plugin/read failures must
  leave iOS advertising tracking disabled without preventing normal app use.
- Subscribe to `statusChanged`, then query `getStatus()` for initial state. Events
  are not retained; always re-query after a page reload. Remove the listener when
  the consumer unmounts.
- Only `authorized` permits ATT-controlled tracking. An unavailable decision is
  not consent. No status is persisted by this plugin.
- The native launch path requests automatically. `requestAuthorization()` is also
  available for an explicit retry after other permission dialogs have finished.
  Concurrent requests share one native prompt. Inactive requests reject with
  `APP_NOT_ACTIVE`; requests after a decision return the current status.
- `statusChanged` is emitted on app activation (including return from Settings)
  and after a request completes. Consumers must handle repeated values.

## Scope and release dependency

This change exposes the system decision and displays the prompt. It does **not**
gate AppsFlyer, AdMob, TikTok Pixel, Web scripts, or server-side event delivery.
WorldSims must prevent tracking before authorization, handle refusal/revocation,
and enforce the same policy on server-side and queued events. Loading the remote
WebView is not delayed by ATT. Do not represent this native change alone as a
complete tracking-consent fix or resubmit it as such.

## Physical-device acceptance checks

1. Fresh install/reset tracking permissions: launch while system tracking requests
   are allowed, verify purpose text and one ATT prompt.
2. Allow: both the returned status and subsequent query report `authorized`.
3. Deny: queries report `denied` and navigation, login and purchases remain usable.
4. Relaunch after either decision: no repeated prompt.
5. Change permission in Settings and return: event and query reflect system state.
6. Disable tracking requests at system level: no forced/repeated prompt; `canTrack`
   remains false. Verify restrictions on a restricted device/account as available.
7. Request while inactive and issue concurrent requests: verify predictable error
   and a single shared request respectively. Test other permission dialogs too;
   if the system returns `notDetermined`, retry only once active after they close.
8. After WorldSims integration, verify actual outgoing traffic for every state and
   record the fresh-install flow on a physical device for App Review.

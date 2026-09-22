# Interactive iOS sheet dismissal

The WorldSims `NativeBackCoordinator` opts into sheet handling with the existing
`NavigationGesture.setEnabled({ enabled: false, sheet: true })` method. Normal
page navigation continues to use `{ enabled: true, sheet: false }`. Both false
blocks gestures (for example when a confirmation dialog covers a detail sheet).
The optional `sheet` parameter defaults to false, preserving existing callers.

In sheet mode WKWebView's back/forward snapshot transition is disabled. A left
screen-edge pan emits `sheetGesture` events with:

- `phase`: `began`, `changed`, `ended`, or `cancelled`;
- `progress`: horizontal translation / WebView width, clamped to 0–1;
- `velocity`: horizontal velocity in WebView widths per second.

The Web `RouteSheet` maps progress onto its remaining vertical travel. It owns
commit/cancel thresholds, the closing animation and the existing sheet-close navigation.
Native must not call `goBack()` or manipulate Web DOM. Disabling the gesture or
backgrounding the App cancels an in-progress pan.

Release the App capability before the matching WorldSims Web caller. Older Web
clients retain existing page gestures. Older Apps ignore `sheet` but honor
`enabled: false`, so an updated Web client safely falls back to its existing
pull-down/close controls instead of showing a page transition.

## Validation

Build the App for iOS Simulator with signing disabled. In a development build
pointed at the matching Web branch, check both world and character detail sheets:

1. Open from the listing, swipe from the left edge: the sheet moves down and the
   listing stays fixed. Complete: return to the listing at its previous scroll.
2. Release before 30%: return to the starting sheet position; history is unchanged.
3. Quick outward flick commits; deliberate reversal cancels. Repeat rapidly: one
   sheet-close action is invoked per dismissal (including its existing internal-history exit).
4. Repeat with a fully expanded/scrolled sheet. Edge dismissal still works while
   ordinary vertical content scrolling and pull-down dismissal keep working.
5. Put a confirmation dialog over the sheet: neither the sheet nor page navigates.
6. Background the App during a pan: no unexpected navigation on return.
7. Normal secondary pages retain WebKit back navigation. Root tabs remain blocked.
8. At desktop/tablet sheet layout widths (640px and above), use existing close
   controls; don't move a centered card vertically with the phone gesture.

The Web branch includes a deterministic gesture controller regression test:
`node --experimental-strip-types scripts/test-native-sheet-gesture.mjs`.

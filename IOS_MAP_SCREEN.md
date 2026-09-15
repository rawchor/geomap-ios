# Geomap iOS — Map Screen

Priority item: right now iOS can log in but shows nothing after that (`SignedInPlaceholderView`). This screen is what makes the app actually demoable. Build this before Register — you can test against an account created via curl or the web `/register` page hitting the same backend.

---

## Before starting

Run the backend's dev seed script against your test account so there's real friend data to render against:
```bash
curl -X POST "http://localhost:8080/dev/seed?email=<your-test-account-email>"
```
Don't build this screen against an empty map.

---

## 1. Location permission + own position

- Request `NSLocationWhenInUseUsageDescription` authorization via `CLLocationManager` on first appearance of this screen (not at app launch — ask when it's contextually needed)
- Handle the denied/restricted case gracefully: show a message explaining the map needs location access, with a button linking to Settings (`UIApplication.openSettingsURLString`) — don't just show a blank map with no explanation
- Once authorized, center the `Map` view on the user's current coordinate

## 2. Friend data — fetch + polling

- On appear: call `APIClient.nearbyFriends`, populate annotations
- Timer-based polling every **15 seconds** (matches web's exact interval — keep both platforms consistent rather than picking a different number independently)
- Also call `APIClient.updateLocation` on the same cadence, posting the device's current coordinate
- On `.unauthorized` from either call: clear the Keychain session and route back to Login (mirrors web's 401-triggers-redirect behavior)
- Empty state: if `nearbyFriends` returns an empty array, show a "No friends nearby yet" message overlaid on the map (not an error state — map should still render normally, centered on the user)

## 3. Avatar markers

- Custom `MapAnnotation`/`Annotation` content (not a default pin) for both the user's own position and each friend:
  - Circular avatar — `AsyncImage` loading `profilePhotoUrl` if present, with a fallback view showing the initial letter of `displayName` on a colored background if the URL is nil or fails to load
  - **Your own marker**: distinct styling (e.g., a colored ring or slightly larger size) so it's unambiguous which one is you — same principle as `WEB_MAP_UPGRADE.md`
  - **Friend markers**: ring color by `degree` — one color for `FIRST_DEGREE`, a visually distinct one for `SECOND_DEGREE`. Match the same two colors web ends up using in `WEB_MAP_UPGRADE.md` once that's implemented, so the two platforms are visually consistent — check in with the web session's final color choices before finalizing here, or use a placeholder pair now and adjust later.
- Tapping a friend's marker opens the Friend Detail sheet (see below)

## 4. 20km radius boundary

- Add an `MKCircle` overlay centered on the user's current location, radius `20_000` meters
- Render via `MapCircle` (SwiftUI MapKit) or an `MKOverlayRenderer` if using `MKMapView`-in-`UIViewRepresentable` — subtle stroke, not a heavy border
- **Gray-out fill outside the circle**: this is the harder piece. If a clean approach isn't quickly achievable (MapKit doesn't have a built-in "mask everything outside this shape" primitive any more than Leaflet does), ship the boundary circle alone first and flag the gray-out fill as a follow-up — same fallback path as web. Don't sink disproportionate time into this on the first pass.

## 5. Friend Detail sheet

- Triggered by tapping a friend annotation, presented as a `.sheet`
- Contents:
  - Large avatar, `displayName`
  - Connection context: `"Direct friend"` for `FIRST_DEGREE`, `"Friends with \(mutualFriendName)"` for `SECOND_DEGREE` — exact copy matching web's `FriendDetailPanel` for consistency
  - Status: preset label (map `StatusPreset` cases to display text) or `customText` if present; `"No status set"` in a neutral/muted style if `status` is `nil` — not an error or missing-data appearance
- Dismissible via swipe-down (standard sheet behavior) or an explicit close button

---

## Explicitly not this pass

- Satellite/map-style toggle (web is building this; port over once proven)
- The gray-out fill, if it turns out to be a time sink (see above)
- MultipeerConnectivity, status-setting — already deferred per `IOS_IMPLEMENTATION.md`

---

## Instructions for Claude Code

1. Branch: `feature/map-screen`
2. Build order: own-location centering → friend fetch/polling with plain default pins first (fast checkpoint: confirm data flow works) → swap to custom avatar annotations → radius boundary → Friend Detail sheet
3. Test against the real backend with seeded data, not a mock — confirm both `FIRST_DEGREE` and `SECOND_DEGREE` friends render with correct styling, and that Julia (the seeded out-of-radius friend) correctly does **not** appear
4. Commit as `[IOS-v0.2.0-SNAPSHOT] Add Map screen with friend visibility` once verified working
5. Update `IMPLEMENTATION_STATUS.md` to reflect what's done and what's deferred, same as previous passes

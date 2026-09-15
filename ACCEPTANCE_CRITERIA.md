# Geomap — Acceptance Criteria (MVP1)

Mobile-first (iOS primary target for MVP1; web is a secondary/companion surface). Each section lists assumptions made where the original request left a detail open — flag any that are wrong and I'll adjust before this goes to Claude Code.

---

## 1. Authentication

- [ ] User can register with email + password
- [ ] User can log in with email + password
- [ ] On successful login, user is taken directly to the Main Map screen
- [ ] Invalid credentials show a clear inline error, no crash/blank state
- [ ] Session persists (JWT stored securely — Keychain on iOS) so the user isn't logged out on every app relaunch
- [ ] Logout available from a settings/profile area (not specified yet — assumed minimal placeholder for MVP1)

**Assumption**: "standard login" = email/password. No social login (Apple/Google Sign-In) in MVP1 unless you want it added.

---

## 2. Main Map Screen

- [ ] On load, map centers on the user's current location (device GPS)
- [ ] A visible boundary (e.g., shaded circle edge or radial gradient) marks a **20 km radius** around the user
- [ ] Area **outside** the 20 km radius is visually grayed out / desaturated / dimmed — clearly distinct from the active area
- [ ] Area outside the radius is **non-interactive** (no tapping friend icons, no panning to reveal hidden info beyond the boundary) — or at minimum, panning is allowed but no friend data loads/renders outside radius
- [ ] Radius is fixed at 20 km for all free-tier users in MVP1 (no subscription logic yet — see Out of Scope)
- [ ] Map updates the user's own position as they move (standard live location dot)

**Assumption**: the grayed-out area can still be panned/viewed (like a "fog of war" aesthetic) but shows no data — rather than being fully locked/unscrollable. Flag if you want hard map-bounds instead.

---

## 3. Friend Visibility on Map

- [ ] Any friend (1st or 2nd degree — see Section 5) currently within the 20 km radius appears as an icon/avatar on the map at their live location
- [ ] Friends outside the 20 km radius do **not** appear at all (not even as a "somewhere out there" indicator in MVP1)
- [ ] Friend icons update via periodic polling every **10–30 seconds** while the map screen is active, and immediately on manual page refresh/pull-to-refresh
- [ ] Visually distinguish 1st-degree friends from 2nd-degree friends (friends-of-friends) on the map via icon border color/style — both are shown with equal prominence, no extra tap/toggle required to reveal 2nd-degree friends

**Decided**: polling (10–30s) over WebSocket push for MVP1 — simpler to build and sufficient for this use case. WebSocket infra from the backend can be revisited for a push-based upgrade post-MVP1 if needed.

---

## 4. Adding Friends (MultipeerConnectivity)

- [ ] "Add Friend" action available from the main screen (e.g., a button that opens a proximity-add screen)
- [ ] Both users must have the app open and tap "Add Friend" / "Nearby" at roughly the same time for devices to discover each other
- [ ] Uses MultipeerConnectivity (`MCNearbyServiceAdvertiser` + `MCNearbyServiceBrowser`) to detect nearby devices running the app
- [ ] Once two devices connect, exchange user IDs directly (peer-to-peer), then call the backend to create the friend relationship — friendship is only persisted after backend confirmation, not purely on-device
- [ ] After MultipeerConnectivity establishes a connection and exchanges user IDs, **each side must separately confirm/accept** before the friendship is created — the proximity connect alone is not sufficient
- [ ] Confirmation screen shows the other person's name/photo (pulled from backend once IDs are exchanged) with clear "Confirm" / "Cancel" actions on both devices
- [ ] Friendship is only persisted to the backend once **both** sides have confirmed — if one side cancels or times out, no friend relationship is created on either side
- [ ] Clear success feedback (e.g., "You and [Name] are now friends") shown on both devices once both confirmations complete
- [ ] Handle failure gracefully (no nearby device found, connection timeout, one side cancels) with a retry option
- [ ] This is the **only** way to add a 1st-degree friend in MVP1 — no search-by-username, no invite links

**Decided**: two-sided explicit confirmation required — prevents accidental adds from stray proximity connections.

**Assumption**: no invite/QR fallback for MVP1 (e.g., if one person doesn't have Bluetooth/proximity working). Confirm if you want a backup path later — noting it's explicitly out of scope for now per your original spec ("the only way to add friends is to touch their phones").

---

## 5. Friend Network — Two Branches

- [ ] **Branch 1 — Direct friends**: users you've personally added via the proximity method
- [ ] **Branch 2 — Friends of friends**: users connected to your direct friends (2nd-degree), visible on the map but not directly "added" by you
- [ ] Backend relationship model must support traversing to 2nd-degree connections (friend's friend list) without exposing 3rd-degree+ in MVP1
- [ ] A 2nd-degree friend only appears if **at least one** of your direct friends has them as a direct friend too (standard mutual-connection graph traversal, depth = 2)

**Decided**: 2nd-degree friends are visible on the map exactly like 1st-degree (just visually distinguished per Section 3), not hidden behind an extra tap.

---

## 6. Friend Detail Popup (tap icon on map)

- [ ] Tapping a friend's icon opens a detail view/bubble showing:
  - Their name/photo
  - **Connection context**: how you know them
    - If 1st-degree: shown simply as a direct friend (e.g., "Added [date/location]" or similar — exact copy TBD)
    - If 2nd-degree: shows **through whom** you're connected (e.g., "Friends with [Mutual Friend Name]")
  - **Status bubble**: a short user-set message describing what they're currently up to / open to (e.g., "Grabbing coffee ☕", "Free to hang")
- [ ] Status message is set by each user themselves via a preset list of common options (e.g., "Free to hang", "Grabbing coffee", "Busy") **plus** an optional custom free-text field for anything not covered by presets
- [ ] **Status is optional** — a user is not required to have one set. Friends with no status simply show no status bubble (or an empty/neutral state) when tapped, not an error or placeholder text.
- [ ] Custom free-text status needs a reasonable length limit (e.g., 60–80 characters) and basic profanity/abuse filtering before going live
- [ ] When setting a status, the user **picks an expiry** at the same time — options: e.g., 1 hour / 4 hours / "until I change it"
- [ ] Status automatically clears (reverts to no status shown) once its chosen expiry passes — backend needs a scheduled check or lazy expiry-on-read to enforce this
- [ ] Detail view is dismissible (tap outside, swipe down, or close button) returning to the map

**Decided**: presets + optional custom text, with user-chosen expiry (1h / 4h / until changed).

---

## 7. Out of Scope for MVP1 (explicitly deferred)

- Subscription tier / paid unlock of worldwide visibility beyond 20 km — architecture should not block this later (e.g., radius should be a configurable value per user/plan, not hardcoded in a way that requires a rewrite), but no payment integration, no plan selection UI, no billing in MVP1
- Web app: full parity with iOS is not required for MVP1 — web needs login + map + view friends (per earlier PROJECT.md scope); MultipeerConnectivity-based friend-adding is iOS/mobile-only by nature, so web has no "Add Friend" flow in MVP1
- Android app
- 3rd-degree+ friend visibility
- Blocking/removing friends, privacy controls beyond radius (e.g., "invisible mode") — reasonable to flag as fast-follow, not MVP1

---

## Decisions Log

All open questions from the initial draft have been resolved:

1. **Location refresh**: polling every 10–30s + on manual refresh (not WebSocket push for MVP1)
2. **Friend-add confirmation**: two-sided explicit confirm required after MultipeerConnectivity proximity connect
3. **Status message**: presets + optional custom free text (with length limit/basic moderation)
4. **Status expiry**: user picks at set time — 1h / 4h / until manually changed
5. **2nd-degree friend visibility**: same map treatment as 1st-degree, visually distinguished by icon styling only

No remaining open questions — ready for Claude Code to begin implementation against this spec.

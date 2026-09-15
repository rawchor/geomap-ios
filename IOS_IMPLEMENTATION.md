# Geomap iOS — Skeleton Implementation Instructions

Scope for this pass: get the same functional baseline web already has (auth + map + friend visibility), as a skeleton to build on. **MultipeerConnectivity friend-adding is explicitly out of scope for this pass** — that's a separate, more complex feature to tackle once this skeleton works end-to-end against the real backend.

Read `API_CONTRACT.json` for exact request/response shapes before implementing anything below — this doc describes structure and flow, the contract file is the source of truth for field names/types.

---

## 1. Networking layer

- `APIClient`: a thin wrapper around `URLSession`, base URL from a config value (not hardcoded — use an `.xcconfig` or a simple `Config.swift` with a `#if DEBUG` switch between local (`http://localhost:8080`) and a future production URL)
- One method per endpoint (`register`, `login`, `me`, `updateLocation`, `nearbyFriends`), each returning a `Codable` response type or throwing a typed `APIError`
- Attach `Authorization: Bearer <token>` automatically for authenticated endpoints by reading from the Keychain-backed session (see below) — don't scatter token-attachment logic across call sites
- Model errors as an enum (`APIError.unauthorized`, `.validationFailed([String: String])`, `.server(Int)`, `.network(Error)`, etc.) so screens can react appropriately (e.g., `.unauthorized` triggers a logout/redirect-to-login, matching web's 401 handling on the friends poll)

## 2. Models

Codable structs matching `API_CONTRACT.json` exactly — field names, optionality, and enum cases (`FIRST_DEGREE`/`SECOND_DEGREE` for `degree`, matching preset values for `Status.preset`). Suggested set:
- `User` (id, email, displayName, profilePhotoUrl)
- `AuthResponse` (token, user)
- `NearbyFriend` (userId, displayName, profilePhotoUrl, latitude, longitude, degree, mutualFriendName, status)
- `FriendStatus` (preset, customText) — nullable as a whole, matching the backend's "empty status is valid" design

## 3. Auth / session (Keychain)

- `KeychainService`: wraps `Security` framework calls to store/retrieve/delete the JWT securely — this is iOS's equivalent of web's httpOnly cookie approach (secure, not casually readable)
- `SessionStore`: an `ObservableObject` holding current auth state (`loggedIn` / `loggedOut`, current `User`), backing the app's root navigation decision (show login flow vs. main app)
- On app launch: check Keychain for a stored token → if present, call `GET /me` to validate it (mirrors web's `/map` server-side validation) → if valid, go straight to the map screen; if invalid/expired, clear the Keychain entry and show login

## 4. Screens

### Login
- Email + password fields, submit button
- Calls `APIClient.login`, on success stores token in Keychain and updates `SessionStore`
- Inline error display for `400`/`401` responses, surfacing the backend's actual message (matching web's approach of not inventing custom copy)

### Register
- Display name, email, password fields
- Calls `APIClient.register` — confirmed in scope for iOS too (matches web's resolution to keep it on both platforms)
- Same error-handling pattern as login

### Map
- SwiftUI `Map` view (MapKit), centered on the user's own location (`CLLocationManager`)
- On appear and on a timer (10–30s, matching the web polling rate already implemented — reuse that exact interval for consistency across platforms): call `APIClient.nearbyFriends`, update annotations
- Post the user's own location periodically too (`APIClient.updateLocation`), same cadence
- Render each friend as a custom annotation — avatar image (or initials fallback) in a circular frame, ring color by `degree`, matching the visual language web is implementing (`WEB_MAP_UPGRADE.md`) so both platforms feel consistent
- Tapping an annotation opens the Friend Detail screen (sheet/popover)
- Empty state ("No friends nearby yet") when the response is empty — not an error
- 20km radius boundary + grayed-out area outside it, mirroring the web implementation — MapKit equivalent: an `MKCircle` overlay for the boundary, and an overlay technique for the gray-out (MapKit doesn't have Leaflet's exact masking approach; simplest cross-platform-consistent option is an `MKPolygon` with the circle as an interior cutout, rendered via `MKOverlayRenderer`). If this proves fiddly, same fallback as web: ship the boundary circle alone first, revisit the gray-out fill separately.

### Friend Detail (sheet)
- Name, avatar (large), connection context ("Direct friend" for 1st-degree, "Friends with {mutualFriendName}" for 2nd-degree — same copy pattern as web's `FriendDetailPanel`)
- Status: preset label or custom text, or a neutral "No status set" when `status` is `null`
- Dismissible via swipe-down or close button (standard sheet behavior)

---

## Explicitly deferred (not this pass)

- MultipeerConnectivity friend-adding flow — separate doc/pass once this skeleton is verified working
- Setting your own status — deferred to whichever platform builds it first; flag which you want to build it on
- Satellite/map-style toggle — nice-to-have parity with web, not blocking for skeleton

---

## Instructions for Claude Code

1. Read `PROJECT.md`, `ACCEPTANCE_CRITERIA.md`, and `API_CONTRACT.json` first
2. Branch: `feature/skeleton-auth-map`
3. Build order: networking layer + models → Keychain/session → login/register screens → map screen (without the radius overlay first, get friends rendering as a fast checkpoint) → friend detail sheet → radius overlay last
4. Follow the commit convention: `[IOS-vX.Y.Z] Description`, version tracked in the Xcode target's Marketing Version field
5. Test against the real running backend locally (same as web's verification pass) — not a mock, and definitely run the backend's dev seed script first (`DEV_SEED_SCRIPT.md`) so there's real friend data to render against, same as the web checkpoint
6. Commit as `[IOS-v0.2.0-SNAPSHOT] Add skeleton: auth, map, friend visibility` once the full flow works end-to-end

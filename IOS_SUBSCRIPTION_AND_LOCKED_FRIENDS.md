# Backend Update — Subscription Tier + Locked Out-of-Radius Friends

For the iOS session. Two backend changes land together, both affecting `GET /friends/nearby` and auth responses. Not yet merged to `main` — currently on branches `feature/subscription-tier` (PR [#7](https://github.com/rawchor/geomap-backend/pull/7)) → `feature/locked-out-of-radius-preview` (PR [#8](https://github.com/rawchor/geomap-backend/pull/8)). `API_CONTRACT.json` in the backend repo root already reflects both.

---

## 1. Subscription tier

`AuthResponse` (returned by `POST /auth/register`, `POST /auth/login`, `GET /auth/me`) has a new field:

```json
"subscriptionTier": "FREE"  // or "PREMIUM"
```

- New users default to `"FREE"`.
- No payment integration exists yet — this is a data flag only. The only way to flip an account to `PREMIUM` right now is a dev-only endpoint (`POST /dev/set-tier?email=...&tier=PREMIUM`, requires the backend running with `spring.profiles.active=dev`).
- Effect: a `PREMIUM` account's `/friends/nearby` has no radius restriction at all — every confirmed 1st/2nd-degree friend with a location comes back, regardless of distance.

**What this needs on iOS**: decode `subscriptionTier` onto your session/user model. Nothing else is required to build yet unless you're doing UI for it — there's no plan-selection screen or upgrade flow to build against, since none exists server-side.

---

## 2. Out-of-radius friends now appear, as locked previews

**This reverses the original MVP1 decision** in `ACCEPTANCE_CRITERIA.md` ("friends outside the 20km radius do not appear at all, not even as a 'somewhere out there' indicator"). That's intentionally changed now: it's a premium-upsell teaser.

Every entry in the `GET /friends/nearby` array now has a new field:

```json
"locked": true  // or false
```

- `locked: false` — everything works as before: full status, normal marker.
- `locked: true` — this friend is a `FREE`-tier user's confirmed friend who is **outside** the 20km radius. They're now included in the response (previously they'd have been omitted entirely) so their marker can render at the correct position, but:
  - `status` is **always `null`** for a locked entry, even if that friend has an actual status set — the backend withholds it unconditionally, not just as a client-side convention.
  - `displayName`, `profilePhotoUrl`, `latitude`, `longitude`, `degree`, `mutualFriendName` are all populated normally — nothing else is hidden.
- `PREMIUM` accounts never receive `locked: true` — they have no radius restriction, so nothing is ever out of range for them.

**What this needs on iOS** (this is the part to actually build):
- Render `locked: true` friends as a marker using their real `profilePhotoUrl`/initials, but at **reduced opacity** — the specific ask was "profile picture but with opacity that doesn't allow to see them [clearly]."
- Disable interaction for locked markers — no tap-through to the Friend Detail sheet (or if tapped, it shouldn't show a working status/contact view, since there's nothing there — `status` will always be `null`). Whether tapping does nothing vs. shows some "upgrade to see more" prompt is a product/UI call on your end; the backend gives you the flag, not a specific UI mandate.
- No new network call needed — locked friends come back in the same `/friends/nearby` array as everyone else, just flagged.

---

## Example response (mixed)

```json
[
  {
    "userId": "...",
    "displayName": "Anna",
    "profilePhotoUrl": null,
    "latitude": 52.2566,
    "longitude": 21.0122,
    "degree": "FIRST_DEGREE",
    "mutualFriendName": null,
    "status": { "preset": "FREE_TO_HANG", "customText": null },
    "locked": false
  },
  {
    "userId": "...",
    "displayName": "Julia",
    "profilePhotoUrl": null,
    "latitude": 52.5441,
    "longitude": 21.0122,
    "degree": "SECOND_DEGREE",
    "mutualFriendName": "Anna",
    "status": null,
    "locked": true
  }
]
```

---

## Testing against the backend

Backend must run with `SPRING_PROFILES_ACTIVE=dev` for the dev-only endpoints below.

- `POST /dev/seed?email=<your-account-email>` — seeds Anna/Marek/Tomek (inside 20km) and Julia (outside, ~35km — this is your locked-preview test case) as friends of the given account. Idempotent, safe to re-run.
- `POST /dev/set-tier?email=<your-account-email>&tier=PREMIUM` — flips an account to premium so you can confirm Julia becomes `locked: false` with a real status once premium is active, then flip back to `tier=FREE` to see it lock again.

**Heads up**: the seed script's fake friends (Anna/Marek/Julia/Tomek) are shared rows across whoever is testing against the same dev database — re-seeding for a different account retargets their friendships away from you. If your seeded friends vanish, it's very likely someone (possibly me) re-ran `/dev/seed` for a different account in the meantime — just re-run it for your own account again.

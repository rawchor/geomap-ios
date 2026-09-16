# Geomap Backend — Error Response Shapes

Verified live against a running server (`SPRING_PROFILES_ACTIVE=dev`), not inferred. One consistent top-level shape across every error case in this app — status, error type, and per-field detail vary, but the JSON envelope never does:

```json
{
  "timestamp": "2026-09-16T10:23:13.417306Z",
  "status": 400,
  "message": "string",
  "fieldErrors": { "fieldName": "string" } | null
}
```

- `fieldErrors` is only ever non-null for validation failures (`400`). Every other error type sends `fieldErrors: null` explicitly (not omitted) — Jackson serializes the field either way, so clients can rely on the key always being present.
- No stack traces, no Spring Boot default Whitelabel/`/error` page, no bare-status-empty-body responses reach the client for any case below.

---

## 400 — Validation failure (well-formed JSON, invalid field values)

`POST /auth/register` with a missing/invalid field:

```json
{
  "timestamp": "2026-09-16T10:23:13.417306Z",
  "status": 400,
  "message": "Validation failed",
  "fieldErrors": { "email": "must not be blank" }
}
```

Other observed field messages: `"must be a well-formed email address"`, `"size must be between 8 and 72"`, `"must be less than or equal to 90.0"` (out-of-range latitude on `POST /location`). Note: when a single field fails *multiple* constraints (e.g. an empty password fails both `@NotBlank` and `@Size`), only one message survives per field — which one is not guaranteed deterministic across requests, since `fieldErrors` is a `field → message` map. Not fixed; documenting as expected, not a bug — a client only needs *a* correct message per field, not an exhaustive list.

## 400 — Malformed JSON syntax (as opposed to well-formed JSON with bad values)

```json
{
  "timestamp": "2026-09-16T10:23:12.889182Z",
  "status": 400,
  "message": "Malformed request body",
  "fieldErrors": null
}
```

This is a distinct case from the validation failure above — no field can be attributed, since the body couldn't be parsed into an object at all.

## 401 — Invalid credentials

`POST /auth/login` with either a non-existent email or a wrong password — **deliberately identical** for both, so a client (or attacker) can't distinguish "no such account" from "wrong password":

```json
{
  "timestamp": "2026-09-16T10:23:13.692210Z",
  "status": 401,
  "message": "Invalid email or password",
  "fieldErrors": null
}
```

## 401 — Missing or invalid authentication

Any authenticated endpoint (`/auth/me`, `/location`, `/friends/nearby`) called with no `Authorization` header, or a garbage/malformed/expired JWT:

```json
{
  "timestamp": "2026-09-16T10:23:14.051391Z",
  "status": 401,
  "message": "Authentication required",
  "fieldErrors": null
}
```

## 409 — Conflict (duplicate email)

`POST /auth/register` with an email that's already registered:

```json
{
  "timestamp": "2026-09-16T10:23:13.392455Z",
  "status": 409,
  "message": "Email already registered: finalcheck_1789554192@example.com",
  "fieldErrors": null
}
```

## 500 — Unexpected server error (last resort)

Not one of the doc's enumerated cases, but added defensively: any exception type not otherwise handled now returns this shape rather than Spring Boot's default error page. Logged server-side at `ERROR`; the client never sees exception details.

```json
{
  "timestamp": "...",
  "status": 500,
  "message": "Internal server error",
  "fieldErrors": null
}
```

---

## Two real bugs found and fixed while verifying

1. **Missing/invalid token returned a bare `403` with an empty body**, not the `401` + JSON this doc expected. `403` is also the semantically wrong status here — this app has no authorization tiers, so a genuine "authenticated but forbidden" case can never occur; every failure here is "not authenticated," which is `401`. Fixed with a custom `RestAuthenticationEntryPoint` (see `SecurityConfig`) producing the same `ErrorResponse` JSON shape as everything else. This is a **breaking change** for any client currently branching on `403` for auth failures — `LocationControllerTest`, `AuthControllerTest`, and `FriendsControllerTest` were all updated from `isForbidden()` to `isUnauthorized()` accordingly.

2. **Malformed JSON syntax on a *public* endpoint (`/auth/register`) came back as `401 "Authentication required"`** — badly misleading, since the endpoint needs no auth at all and the real problem was a JSON parse failure. Root cause: `HttpMessageNotReadableException` had no handler, so it propagated uncaught to Spring Boot's internal `/error` forward — a fresh HTTP dispatch that isn't in `SecurityConfig`'s public-path list, so it got rejected as unauthenticated by the very entry point built to fix bug #1. This is the same "unhandled exception masquerades as an auth failure via the `/error` re-dispatch" pattern that's bitten this project more than once before (see `SecurityConfig`'s public-path comments). Fixed with an explicit `HttpMessageNotReadableException` handler, plus a catch-all `Exception` handler so no future unhandled exception type can trigger the same masking again.

# Geomap — Project Brief

A mobile + web app that lets friends see each other's live location on a map, with radius-based visibility (friends only appear if within a configurable distance).

## Stack

**Backend**
- Java 21 (Temurin/OpenJDK)
- Spring Boot 3.x (Maven)
- Spring Web, Spring Data JPA, Spring Security (JWT), Spring WebSocket (STOMP), Validation
- PostgreSQL 16 + PostGIS extension (geospatial radius queries via `ST_DWithin`)
- Hibernate Spatial (PostGIS entity mapping)

**iOS**
- Swift + SwiftUI
- MapKit
- URLSession for REST, URLSessionWebSocketTask for realtime

**Web**
- Next.js (React, TypeScript, App Router)
- Leaflet + react-leaflet (OpenStreetMap tiles — no billing setup required)

**Android**
- Planned post-MVP1. Likely Kotlin + Jetpack Compose + Google Maps SDK or OSMDroid, mirroring the iOS approach.

## Repos (one per platform, no monorepo)

| Repo | Purpose |
|---|---|
| `geomap-backend` | Spring Boot API + WebSocket server |
| `geomap-ios` | Native iOS app |
| `geomap-web` | Next.js landing page + logged-in web app |
| `geomap-android` | Future native Android app |

Each client repo consumes the same backend API. Keep an OpenAPI/Swagger spec (via `springdoc-openapi`) in the backend repo as the source of truth for the API contract across all clients.

## Key architectural decisions

- **Radius filtering happens server-side**, never client-side. The backend only ever returns friends within the requested radius — clients never receive raw location data for out-of-range friends. This is a privacy requirement, not just a performance one.
- **Geospatial queries use PostGIS `ST_DWithin`** on a `GEOGRAPHY(Point)` column, not manual Haversine math in application code.
- **Auth**: Spring Security + JWT. No third-party auth vendor (Firebase/Auth0) — avoids per-MAU pricing and vendor lock-in.
- **Realtime updates**: WebSocket via STOMP, built into Spring — no third-party realtime service.
- **No vendor lock-in philosophy overall**: self-hosted Postgres, self-hosted auth, self-hosted realtime. Only third-party dependency is map tile providers (OSM for web, Apple Maps/MapKit for iOS — both free).

## Versioning convention

Semantic versioning (`MAJOR.MINOR.PATCH`) per repo, with a repo prefix in commit messages, kept in sync with each project's own version file (`pom.xml` `<version>` for backend; equivalent for other repos once established).

**Repo prefixes:**
- Backend: `BE`
- iOS: `IOS`
- Web: `WEB`
- Android: `AND`

**Commit message format:**
```
[PREFIX-vX.Y.Z] Short description
```

**Bump rules:**
- PATCH — bug fix or small tweak, no new feature
- MINOR — new feature (new endpoint, new screen, etc.)
- MAJOR — breaking change, or a real milestone (e.g., MVP1 complete → `v1.0.0`)

**Full Maven SNAPSHOT convention (backend, from the start):**
- While actively working on a version: `pom.xml` version is `X.Y.Z-SNAPSHOT`
- Commits during that work use the target version in the message: `[BE-vX.Y.Z] ...`
- When ready to mark a milestone/release:
  1. Edit `pom.xml`, remove `-SNAPSHOT` → commit: `[BE-vX.Y.Z] Release version X.Y.Z`
  2. `git tag BE-vX.Y.Z`
  3. `git push origin main --tags`
  4. Bump `pom.xml` to the next `-SNAPSHOT` version → commit: `[BE-vX.Y.(Z+1)] Start development`
- Apply the same tag/push pattern (without the Maven-specific SNAPSHOT file edit) to `IOS`, `WEB`, and `AND` repos once each has an equivalent version marker (e.g., Xcode project version, `package.json` version).

## Repo setup so far

- GitHub repos created: `geomap-backend`, `geomap-ios` (web and android repos to follow)
- Backend: Spring Boot project generated via Spring Initializr (Maven, Java 21, Spring Boot 4.1.1, dependencies: Web, Data JPA, PostgreSQL Driver, Security, WebSocket, Validation), merged into the cloned `geomap-backend` repo
- Local environment: JDK 21 (Temurin), IntelliJ IDEA CE, PostgreSQL installed via Homebrew, PostGIS extension enabled, pgAdmin for GUI database access
- iOS: Xcode 26.6 (Apple Silicon) pending install after macOS update to 26.2+; local dev machine is a MacBook with M3 Pro

## MVP1 scope

Goal: backend + iOS + web all working end-to-end, proving the full stack.

1. **Backend**
   - `User` and `Location` entities (PostGIS-mapped)
   - `POST /auth/register`, `POST /auth/login` (JWT)
   - `POST /location` (update authenticated user's location)
   - `GET /friends/nearby?radius=X` (PostGIS `ST_DWithin` query)
2. **Web**
   - Login page
   - Map view (Leaflet) showing nearby friends from `/friends/nearby`
3. **iOS**
   - Login screen
   - Map view (MapKit) showing nearby friends from `/friends/nearby`

MVP1 is considered done when a user can register/log in on both web and iOS, and see friends within radius plotted on a map on both platforms, against the same backend.

## Suggested workflow (per feature)

```
git checkout -b feature/short-name
# build the feature
git add .
git commit -m "[PREFIX-vX.Y.Z] Description"
git push origin feature/short-name
# open PR on GitHub, review, merge to main
git checkout main && git pull
```

import Foundation

enum FriendDegree: String, Decodable {
    case firstDegree = "FIRST_DEGREE"
    case secondDegree = "SECOND_DEGREE"
}

/// Nullable as a whole on `NearbyFriendResponse` — the backend's "empty
/// status is valid" design means a friend simply has no status set.
///
/// Presets are DB-backed now (fetched via `GET /status/presets`), not a
/// fixed enum — this flattens the chosen preset's label/emoji directly
/// onto the response rather than requiring a second lookup by id.
struct StatusResponse: Decodable {
    let presetOptionId: UUID?
    let presetLabel: String?
    let presetEmoji: String?
    let customText: String?
}

struct NearbyFriendResponse: Decodable, Identifiable {
    let userId: UUID
    let displayName: String
    let profilePhotoUrl: String?
    let latitude: Double
    let longitude: Double
    let degree: FriendDegree
    /// Only present for second-degree friends ("Friends with {mutualFriendName}").
    let mutualFriendName: String?
    let status: StatusResponse?
    /// A FREE-tier user's confirmed friend outside the 20km radius: included
    /// as an upsell teaser with real position/photo but `status` always nil
    /// (withheld server-side, not just a client convention). PREMIUM
    /// accounts never receive `locked: true`.
    let locked: Bool

    var id: UUID { userId }
}

/// `GET /friends` — confirmed first-degree friends only, independent of
/// location/radius (unlike `NearbyFriendResponse`). No status or location.
struct FriendResponse: Decodable, Identifiable, Equatable {
    let userId: UUID
    let displayName: String
    let profilePhotoUrl: String?

    var id: UUID { userId }
}

// MARK: - Add friend (touch-to-add) — see API_CONTRACT.json /friends/encounter*

struct EncounterTokenResponse: Decodable, Equatable {
    let token: String
    let expiresAt: Date
}

struct EncounterTokenRequest: Encodable {
    let token: String
}

/// Profile of whoever owns an encounter code. Always fetched from the
/// server — never taken from what a peer claims over MultipeerConnectivity.
struct UserProfileResponse: Decodable, Equatable {
    let userId: UUID
    let displayName: String
    let profilePhotoUrl: String?
}

enum FriendConfirmationStatus: String, Decodable {
    case pending = "PENDING"
    case confirmed = "CONFIRMED"
}

struct FriendConfirmResponse: Decodable, Equatable {
    let userId: UUID
    let displayName: String
    let profilePhotoUrl: String?
    let status: FriendConfirmationStatus

    var profile: UserProfileResponse {
        UserProfileResponse(userId: userId, displayName: displayName, profilePhotoUrl: profilePhotoUrl)
    }
}

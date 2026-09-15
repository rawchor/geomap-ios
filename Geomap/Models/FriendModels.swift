import Foundation

enum FriendDegree: String, Decodable {
    case firstDegree = "FIRST_DEGREE"
    case secondDegree = "SECOND_DEGREE"
}

enum StatusPreset: String, Decodable {
    case freeToHang = "FREE_TO_HANG"
    case grabbingCoffee = "GRABBING_COFFEE"
    case busy = "BUSY"
    case outAndAbout = "OUT_AND_ABOUT"
}

/// Nullable as a whole on `NearbyFriendResponse` — the backend's "empty
/// status is valid" design means a friend simply has no status set.
struct FriendStatus: Decodable {
    let preset: StatusPreset?
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
    let status: FriendStatus?
    /// A FREE-tier user's confirmed friend outside the 20km radius: included
    /// as an upsell teaser with real position/photo but `status` always nil
    /// (withheld server-side, not just a client convention). PREMIUM
    /// accounts never receive `locked: true`.
    let locked: Bool

    var id: UUID { userId }
}

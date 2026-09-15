import Foundation

struct RegisterRequest: Encodable {
    let displayName: String
    let email: String
    let password: String
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

enum SubscriptionTier: String, Decodable, Equatable {
    case free = "FREE"
    case premium = "PREMIUM"
}

struct AuthResponse: Decodable {
    let token: String
    let userId: UUID
    let email: String
    let displayName: String
    /// Optional in practice, not just per the OpenAPI schema: accounts
    /// created before this field existed come back with `null` rather than
    /// a backfilled "FREE" (a backend data gap, not documented behavior).
    /// `User.init` treats a missing tier as `.free`.
    let subscriptionTier: SubscriptionTier?
}

/// The signed-in user, derived from `AuthResponse`. The backend's auth
/// endpoints don't return a profile photo for the current user, so this
/// stays a subset of the fields `NearbyFriendResponse` carries for others.
struct User: Equatable {
    let id: UUID
    let email: String
    let displayName: String
    let subscriptionTier: SubscriptionTier

    init(from auth: AuthResponse) {
        self.id = auth.userId
        self.email = auth.email
        self.displayName = auth.displayName
        self.subscriptionTier = auth.subscriptionTier ?? .free
    }
}

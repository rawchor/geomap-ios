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

struct AuthResponse: Decodable {
    let token: String
    let userId: UUID
    let email: String
    let displayName: String
}

/// The signed-in user, derived from `AuthResponse`. The backend's auth
/// endpoints don't return a profile photo for the current user, so this
/// stays a subset of the fields `NearbyFriendResponse` carries for others.
struct User: Equatable {
    let id: UUID
    let email: String
    let displayName: String

    init(from auth: AuthResponse) {
        self.id = auth.userId
        self.email = auth.email
        self.displayName = auth.displayName
    }
}

import Foundation

enum AuthState: Equatable {
    /// Checking Keychain / validating a stored token against `GET /me`.
    case loading
    case loggedOut
    case loggedIn(User)
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var authState: AuthState = .loading

    private let apiClient: APIClient
    private let keychain: KeychainService

    init(apiClient: APIClient = .shared, keychain: KeychainService = .shared) {
        self.apiClient = apiClient
        self.keychain = keychain
    }

    /// Called once at app launch: validates any stored token against the
    /// backend (mirrors web's server-side session check on `/map`).
    func bootstrap() async {
        guard keychain.getToken() != nil else {
            authState = .loggedOut
            return
        }
        do {
            let response = try await apiClient.me()
            authState = .loggedIn(User(from: response))
        } catch {
            keychain.deleteToken()
            authState = .loggedOut
        }
    }

    func login(email: String, password: String) async throws {
        let response = try await apiClient.login(LoginRequest(email: email, password: password))
        keychain.saveToken(response.token)
        authState = .loggedIn(User(from: response))
    }

    func register(displayName: String, email: String, password: String) async throws {
        let response = try await apiClient.register(
            RegisterRequest(displayName: displayName, email: email, password: password)
        )
        keychain.saveToken(response.token)
        authState = .loggedIn(User(from: response))
    }

    func logout() {
        keychain.deleteToken()
        authState = .loggedOut
    }
}

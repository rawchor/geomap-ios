import XCTest
@testable import Geomap

@MainActor
final class SessionStoreTests: XCTestCase {
    private let keychain = KeychainService.shared

    override func tearDown() {
        keychain.deleteToken()
        super.tearDown()
    }

    private func makeStore(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> SessionStore {
        MockURLProtocol.requestHandler = handler
        let apiClient = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: MockURLProtocol.makeSession(),
            tokenProvider: { self.keychain.getToken() }
        )
        return SessionStore(apiClient: apiClient, keychain: keychain)
    }

    func testBootstrapWithNoStoredTokenGoesToLoggedOut() async {
        keychain.deleteToken()
        let store = makeStore { _ in
            XCTFail("Should not call the network without a stored token")
            throw URLError(.unknown)
        }

        await store.bootstrap()

        XCTAssertEqual(store.authState, .loggedOut)
    }

    func testBootstrapWithValidStoredTokenGoesToLoggedIn() async {
        keychain.saveToken("valid-token")
        let store = makeStore { request in
            let body = """
            {"token":"valid-token","userId":"d39ad7d6-d739-4874-b716-ad81ded6a1f5","email":"a@b.com","displayName":"A"}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        await store.bootstrap()

        guard case .loggedIn(let user) = store.authState else {
            return XCTFail("Expected .loggedIn, got \(store.authState)")
        }
        XCTAssertEqual(user.displayName, "A")
    }

    func testBootstrapWithExpiredTokenClearsKeychainAndLogsOut() async {
        keychain.saveToken("expired-token")
        let store = makeStore { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }

        await store.bootstrap()

        XCTAssertEqual(store.authState, .loggedOut)
        XCTAssertNil(keychain.getToken())
    }

    func testLoginSuccessSavesTokenAndUpdatesState() async throws {
        keychain.deleteToken()
        let store = makeStore { request in
            let body = """
            {"token":"fresh-token","userId":"d39ad7d6-d739-4874-b716-ad81ded6a1f5","email":"a@b.com","displayName":"A"}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        try await store.login(email: "a@b.com", password: "password123")

        XCTAssertEqual(keychain.getToken(), "fresh-token")
        guard case .loggedIn = store.authState else {
            return XCTFail("Expected .loggedIn, got \(store.authState)")
        }
    }

    func testLoginFailureThrowsAndDoesNotSaveToken() async {
        keychain.deleteToken()
        let store = makeStore { request in
            let body = #"{"message":"Invalid email or password."}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, body)
        }

        do {
            try await store.login(email: "a@b.com", password: "wrong")
            XCTFail("Expected login to throw")
        } catch {
            // expected
        }

        XCTAssertNil(keychain.getToken())
    }

    func testLogoutClearsTokenAndState() {
        keychain.saveToken("some-token")
        let store = makeStore { _ in throw URLError(.unknown) }

        store.logout()

        XCTAssertEqual(store.authState, .loggedOut)
        XCTAssertNil(keychain.getToken())
    }
}

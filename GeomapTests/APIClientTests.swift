import XCTest
@testable import Geomap

final class APIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeClient(token: String? = nil) -> APIClient {
        APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: MockURLProtocol.makeSession(),
            tokenProvider: { token }
        )
    }

    func testLoginSuccessDecodesAuthResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"token":"abc","userId":"d39ad7d6-d739-4874-b716-ad81ded6a1f5","email":"a@b.com","displayName":"A","subscriptionTier":"FREE"}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let client = makeClient()
        let result = try await client.login(LoginRequest(email: "a@b.com", password: "password123"))

        XCTAssertEqual(result.token, "abc")
        XCTAssertEqual(result.email, "a@b.com")
    }

    func testLoginWithBadCredentialsThrowsUnauthorizedWithBackendMessage() async {
        MockURLProtocol.requestHandler = { request in
            let body = #"{"message":"Invalid email or password."}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let client = makeClient()
        do {
            _ = try await client.login(LoginRequest(email: "a@b.com", password: "wrong"))
            XCTFail("Expected APIError.unauthorized")
        } catch let error as APIError {
            guard case .unauthorized(let message) = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
            XCTAssertEqual(message, "Invalid email or password.")
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    func testRegisterWithValidationErrorSurfacesFieldMessages() async {
        MockURLProtocol.requestHandler = { request in
            let body = #"{"timestamp":"2026-01-01T00:00:00Z","status":400,"message":"Validation failed","fieldErrors":{"email":"must be a valid email"}}"#.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let client = makeClient()
        do {
            _ = try await client.register(RegisterRequest(displayName: "A", email: "not-an-email", password: "password123"))
            XCTFail("Expected APIError.validationFailed")
        } catch let error as APIError {
            guard case .validationFailed(let errors) = error else {
                return XCTFail("Expected .validationFailed, got \(error)")
            }
            XCTAssertEqual(errors["email"], "must be a valid email")
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    func testChatMessagesBuildsCorrectPathAndQueryItems() async throws {
        let friendId = UUID()
        let before = Date(timeIntervalSince1970: 1_700_000_000)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url!.path, "/chat/\(friendId)/messages")
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            let queryDict = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
            XCTAssertEqual(queryDict["limit"], "20")
            XCTAssertNotNil(queryDict["before"])
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
        }

        let client = makeClient(token: "test-token")
        let messages = try await client.chatMessages(friendId: friendId, before: before, limit: 20)

        XCTAssertTrue(messages.isEmpty)
    }

    func testMyStatusWithEmptyResponseBodyDecodesAsNoStatusSet() async throws {
        // Verified live: GET /status/me returns Content-Length: 0 (not
        // `{}`) when no status is set — undocumented in the OpenAPI
        // schema. Must decode successfully rather than throw .decoding.
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data())
        }

        let client = makeClient(token: "test-token")
        let status = try await client.myStatus()

        XCTAssertNil(status.displayText)
    }

    func testAuthenticatedEndpointAttachesBearerToken() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let body = "[]".data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let client = makeClient(token: "test-token")
        let friends = try await client.nearbyFriends()
        XCTAssertTrue(friends.isEmpty)
    }

    func testExpiredTokenOnProtectedEndpointReturns401WithParsedMessage() async {
        // Regression coverage for ERROR_SHAPES.md's documented fix: this
        // used to come back as a bare 403 with an empty body — the server
        // now sends 401 with the same envelope as every other error case.
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"timestamp":"2026-09-16T10:23:14.051391Z","status":401,"message":"Authentication required","fieldErrors":null}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, body)
        }

        let client = makeClient(token: "expired-token")
        do {
            _ = try await client.nearbyFriends()
            XCTFail("Expected APIError.unauthorized")
        } catch let error as APIError {
            guard case .unauthorized(let message) = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
            XCTAssertEqual(message, "Authentication required")
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    func testAuthenticatedEndpointWithoutStoredTokenThrowsUnauthorized() async {
        let client = makeClient(token: nil)
        do {
            _ = try await client.nearbyFriends()
            XCTFail("Expected APIError.unauthorized")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }
}

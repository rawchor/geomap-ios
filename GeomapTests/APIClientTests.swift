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
            let body = #"{"errors":{"email":"must be a valid email"}}"#.data(using: .utf8)!
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

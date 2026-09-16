import XCTest
@testable import Geomap

@MainActor
final class RegisterViewModelTests: XCTestCase {
    private let keychain = KeychainService.shared

    override func tearDown() {
        keychain.deleteToken()
        super.tearDown()
    }

    private func makeSessionStore(handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> SessionStore {
        MockURLProtocol.requestHandler = handler
        let apiClient = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: MockURLProtocol.makeSession(),
            tokenProvider: { self.keychain.getToken() }
        )
        return SessionStore(apiClient: apiClient, keychain: keychain)
    }

    func testCannotSubmitUntilEmailAndAnEightCharacterPasswordAreSet() {
        let viewModel = RegisterViewModel()
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.email = "a@b.com"
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.password = "short"
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.password = "password123"
        XCTAssertTrue(viewModel.canSubmit)
    }

    func testSubmitSuccessClearsErrorMessage() async {
        let store = makeSessionStore { request in
            let body = """
            {"token":"t","userId":"d39ad7d6-d739-4874-b716-ad81ded6a1f5","email":"a@b.com","displayName":"A","subscriptionTier":"FREE"}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, body)
        }
        let viewModel = RegisterViewModel()
        viewModel.displayName = "A"
        viewModel.email = "a@b.com"
        viewModel.password = "password123"

        await viewModel.submit(using: store)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testSubmitFailureSurfacesValidationMessage() async {
        let store = makeSessionStore { request in
            let body = #"{"timestamp":"2026-01-01T00:00:00Z","status":400,"message":"Validation failed","fieldErrors":{"email":"already registered"}}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, body)
        }
        let viewModel = RegisterViewModel()
        viewModel.email = "a@b.com"
        viewModel.password = "password123"

        await viewModel.submit(using: store)

        XCTAssertEqual(viewModel.errorMessage, "already registered")
        XCTAssertFalse(viewModel.isSubmitting)
    }
}

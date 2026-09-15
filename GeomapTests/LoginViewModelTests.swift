import XCTest
@testable import Geomap

@MainActor
final class LoginViewModelTests: XCTestCase {
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

    func testCannotSubmitWithEmptyFields() {
        let viewModel = LoginViewModel()
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.email = "a@b.com"
        XCTAssertFalse(viewModel.canSubmit)

        viewModel.password = "password123"
        XCTAssertTrue(viewModel.canSubmit)
    }

    func testSubmitSuccessClearsErrorMessage() async {
        let store = makeSessionStore { request in
            let body = """
            {"token":"t","userId":"d39ad7d6-d739-4874-b716-ad81ded6a1f5","email":"a@b.com","displayName":"A"}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let viewModel = LoginViewModel()
        viewModel.email = "a@b.com"
        viewModel.password = "password123"

        await viewModel.submit(using: store)

        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testSubmitFailureSurfacesBackendMessage() async {
        let store = makeSessionStore { request in
            let body = #"{"message":"Invalid email or password."}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, body)
        }
        let viewModel = LoginViewModel()
        viewModel.email = "a@b.com"
        viewModel.password = "wrong"

        await viewModel.submit(using: store)

        XCTAssertEqual(viewModel.errorMessage, "Invalid email or password.")
        XCTAssertFalse(viewModel.isSubmitting)
    }
}

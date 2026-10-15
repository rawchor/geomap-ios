import XCTest
@testable import Geomap

@MainActor
final class SettingsViewModelTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeViewModel() -> SettingsViewModel {
        let apiClient = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: MockURLProtocol.makeSession(),
            tokenProvider: { "test-token" }
        )
        return SettingsViewModel(apiClient: apiClient)
    }

    func testLoadPopulatesFriendsFromFriendsEndpoint() async {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url!.path, "/friends")
            XCTAssertEqual(request.httpMethod, "GET")
            let body = """
            [{"userId":"d39ad7d6-d739-4874-b716-ad81ded6a1f5","displayName":"Anna","profilePhotoUrl":null},
             {"userId":"0b9f3a3e-1f0b-4c3e-9a6e-2f4a0e2f7a11","displayName":"Marek","profilePhotoUrl":"https://example.com/m.png"}]
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.friends.map(\.displayName), ["Anna", "Marek"])
        XCTAssertNil(viewModel.friends[0].profilePhotoUrl)
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadWithEmptyArrayLeavesNoFriends() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
        }

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertTrue(viewModel.friends.isEmpty)
        XCTAssertTrue(viewModel.hasLoaded)
    }

    func testLoadFailureSetsErrorAndStillMarksLoaded() async {
        MockURLProtocol.requestHandler = { request in
            let body = #"{"message":"Boom"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, body)
        }

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.hasLoaded)
    }
}

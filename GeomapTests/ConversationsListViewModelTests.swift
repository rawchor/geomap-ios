import XCTest
@testable import Geomap

@MainActor
final class ConversationsListViewModelTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeViewModel() -> ConversationsListViewModel {
        let apiClient = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: MockURLProtocol.makeSession(),
            tokenProvider: { "test-token" }
        )
        return ConversationsListViewModel(apiClient: apiClient)
    }

    func testLoadPopulatesConversations() async {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url!.path, "/chat/conversations")
            let body = """
            [{"friendId":"d39ad7d6-d739-4874-b716-ad81ded6a1f5","displayName":"Anna","profilePhotoUrl":null,"lastMessage":"see you soon","lastMessageSentAt":"2026-01-01T12:00:00Z"}]
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertEqual(viewModel.conversations.count, 1)
        XCTAssertEqual(viewModel.conversations.first?.displayName, "Anna")
        XCTAssertEqual(viewModel.conversations.first?.lastMessage, "see you soon")
    }

    func testLoadWithNoMessagesYetDecodesNilLastMessage() async {
        MockURLProtocol.requestHandler = { request in
            let body = """
            [{"friendId":"d39ad7d6-d739-4874-b716-ad81ded6a1f5","displayName":"Marek","profilePhotoUrl":null,"lastMessage":null,"lastMessageSentAt":null}]
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertNil(viewModel.conversations.first?.lastMessage)
    }

    func testLoadFailureSurfacesErrorMessage() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let viewModel = makeViewModel()
        await viewModel.load()

        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.conversations.isEmpty)
    }
}

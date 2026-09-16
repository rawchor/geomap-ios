import XCTest
@testable import Geomap

@MainActor
final class ChatViewModelTests: XCTestCase {
    private let currentUserId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let friendId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let otherUserId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeViewModel(socket: MockChatSocket) -> ChatViewModel {
        let apiClient = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: MockURLProtocol.makeSession(),
            tokenProvider: { "test-token" }
        )
        return ChatViewModel(
            friendId: friendId,
            friendDisplayName: "Friend",
            currentUserId: currentUserId,
            apiClient: apiClient,
            socket: socket,
            tokenProvider: { "test-token" }
        )
    }

    func testLoadHistorySortsMessagesBySentAt() async {
        MockURLProtocol.requestHandler = { [friendId, otherUserId] request in
            XCTAssertEqual(request.url!.path, "/chat/\(friendId)/messages")
            let body = """
            [
                {"id":"\(UUID())","senderId":"\(otherUserId)","recipientId":"\(friendId)","content":"second","sentAt":"2026-01-01T12:00:01Z","readAt":null},
                {"id":"\(UUID())","senderId":"\(otherUserId)","recipientId":"\(friendId)","content":"first","sentAt":"2026-01-01T12:00:00Z","readAt":null}
            ]
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let viewModel = makeViewModel(socket: MockChatSocket())
        await viewModel.loadHistory()

        XCTAssertEqual(viewModel.messages.map(\.content), ["first", "second"])
    }

    func testStartConnectsSocketWithToken() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
        }
        let socket = MockChatSocket()
        let viewModel = makeViewModel(socket: socket)

        await viewModel.start()

        XCTAssertEqual(socket.connectedToken, "test-token")
    }

    func testSendCallsSocketAndAppendsOptimisticMessage() {
        let socket = MockChatSocket()
        let viewModel = makeViewModel(socket: socket)
        viewModel.draftText = "hello there"

        viewModel.send()

        XCTAssertEqual(socket.sentMessages.count, 1)
        XCTAssertEqual(socket.sentMessages.first?.recipientId, friendId)
        XCTAssertEqual(socket.sentMessages.first?.content, "hello there")
        XCTAssertEqual(viewModel.messages.last?.content, "hello there")
        XCTAssertEqual(viewModel.messages.last?.senderId, currentUserId)
        XCTAssertEqual(viewModel.draftText, "")
    }

    func testSendWithBlankTextDoesNothing() {
        let socket = MockChatSocket()
        let viewModel = makeViewModel(socket: socket)
        viewModel.draftText = "   "

        viewModel.send()

        XCTAssertTrue(socket.sentMessages.isEmpty)
        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testIncomingMessageFromFriendIsAppended() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
        }
        let socket = MockChatSocket()
        let viewModel = makeViewModel(socket: socket)
        await viewModel.start()

        let incoming = ChatMessageResponse(
            id: UUID(), senderId: friendId, recipientId: currentUserId,
            content: "hi back", sentAt: Date(), readAt: nil
        )
        socket.emit(.message(incoming))

        XCTAssertEqual(viewModel.messages.count, 1)
        XCTAssertEqual(viewModel.messages.first?.content, "hi back")
    }

    func testIncomingMessageFromUnrelatedUserIsIgnored() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
        }
        let socket = MockChatSocket()
        let viewModel = makeViewModel(socket: socket)
        await viewModel.start()

        let unrelated = ChatMessageResponse(
            id: UUID(), senderId: otherUserId, recipientId: currentUserId,
            content: "not for this thread", sentAt: Date(), readAt: nil
        )
        socket.emit(.message(unrelated))

        XCTAssertTrue(viewModel.messages.isEmpty)
    }

    func testIncomingErrorSetsErrorMessage() async {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
        }
        let socket = MockChatSocket()
        let viewModel = makeViewModel(socket: socket)
        await viewModel.start()

        socket.emit(.error("You can only message confirmed friends"))

        XCTAssertEqual(viewModel.errorMessage, "You can only message confirmed friends")
    }

    func testStopDisconnectsSocket() {
        let socket = MockChatSocket()
        let viewModel = makeViewModel(socket: socket)

        viewModel.stop()

        XCTAssertTrue(socket.disconnectCalled)
    }
}

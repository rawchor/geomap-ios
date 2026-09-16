import XCTest
@testable import Geomap

@MainActor
final class UnreadMessagesStoreTests: XCTestCase {
    private let currentUserId = UUID()
    private let annaId = UUID()
    private let marekId = UUID()

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func makeStore(
        notifier: MockNotifier,
        defaults: UserDefaults = UserDefaults(suiteName: UUID().uuidString)!
    ) -> UnreadMessagesStore {
        let apiClient = APIClient(
            baseURL: URL(string: "http://localhost:8080")!,
            session: MockURLProtocol.makeSession(),
            tokenProvider: { "test-token" }
        )
        return UnreadMessagesStore(
            currentUserId: currentUserId,
            apiClient: apiClient,
            notifier: notifier,
            defaults: defaults
        )
    }

    private func conversationsJSON(annaSentAt: String) -> String {
        """
        [{"friendId":"\(annaId)","displayName":"Anna","profilePhotoUrl":null,"lastMessage":"hi","lastMessageSentAt":"\(annaSentAt)"}]
        """
    }

    func testFirstPollEstablishesBaselineWithoutNotifying() async {
        MockURLProtocol.requestHandler = { request in
            let body = self.conversationsJSON(annaSentAt: "2026-01-01T12:00:00Z").data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let notifier = MockNotifier()
        let store = makeStore(notifier: notifier)

        await store.refresh()

        XCTAssertTrue(notifier.posted.isEmpty)
        XCTAssertTrue(store.hasUnread(friendId: annaId))
    }

    func testNewMessageOnSubsequentPollFiresNotification() async {
        var sentAt = "2026-01-01T12:00:00Z"
        MockURLProtocol.requestHandler = { request in
            let body = self.conversationsJSON(annaSentAt: sentAt).data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let notifier = MockNotifier()
        let store = makeStore(notifier: notifier)

        await store.refresh() // baseline, no notification
        sentAt = "2026-01-01T12:05:00Z" // a new message arrives
        await store.refresh()

        XCTAssertEqual(notifier.posted.count, 1)
        XCTAssertEqual(notifier.posted.first?.friendDisplayName, "Anna")
    }

    func testNoNotificationWhenSameConversationIsCurrentlyOpen() async {
        var sentAt = "2026-01-01T12:00:00Z"
        MockURLProtocol.requestHandler = { request in
            let body = self.conversationsJSON(annaSentAt: sentAt).data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let notifier = MockNotifier()
        let store = makeStore(notifier: notifier)
        store.currentlyOpenFriendId = annaId

        await store.refresh()
        sentAt = "2026-01-01T12:05:00Z"
        await store.refresh()

        // Suppressed: this is what prevents a user's own outgoing message
        // (which also advances lastMessageSentAt) from notifying them
        // about their own message while they're sitting in that chat.
        XCTAssertTrue(notifier.posted.isEmpty)
    }

    func testNoNotificationForRecentlySentMessageEvenAfterLeavingTheChat() async {
        // Regression test: this is the actual bug hit in manual testing —
        // currentlyOpenFriendId alone wasn't reliable (the user got
        // notified about their own "Yea I'm down" after sending it), so
        // recordSentMessage is the primary suppression signal now, checked
        // independently of whether the chat is still open.
        let notifier = MockNotifier()
        let store = makeStore(notifier: notifier)
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
        }
        await store.refresh() // baseline: no conversations yet

        store.recordSentMessage(to: annaId)
        store.currentlyOpenFriendId = nil // simulates having already left the chat

        let sentAt = ISO8601DateFormatter().string(from: Date())
        MockURLProtocol.requestHandler = { request in
            let body = self.conversationsJSON(annaSentAt: sentAt).data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        await store.refresh()

        XCTAssertTrue(notifier.posted.isEmpty)
    }

    func testGenuineIncomingMessageStillNotifiesDespiteAnUnrelatedRecentSend() async {
        let notifier = MockNotifier()
        let store = makeStore(notifier: notifier)
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, "[]".data(using: .utf8)!)
        }
        await store.refresh()

        store.recordSentMessage(to: marekId) // sent to someone else entirely

        let sentAt = ISO8601DateFormatter().string(from: Date())
        MockURLProtocol.requestHandler = { request in
            let body = self.conversationsJSON(annaSentAt: sentAt).data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        await store.refresh()

        XCTAssertEqual(notifier.posted.count, 1)
    }

    func testMarkReadClearsUnreadStatus() async {
        MockURLProtocol.requestHandler = { request in
            let body = self.conversationsJSON(annaSentAt: "2026-01-01T12:00:00Z").data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let store = makeStore(notifier: MockNotifier())
        await store.refresh()
        XCTAssertTrue(store.hasUnread(friendId: annaId))

        store.markRead(friendId: annaId)

        XCTAssertFalse(store.hasUnread(friendId: annaId))
        XCTAssertEqual(store.unreadCount, 0)
    }

    func testLastReadPersistsAcrossStoreInstances() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        MockURLProtocol.requestHandler = { request in
            let body = self.conversationsJSON(annaSentAt: "2026-01-01T12:00:00Z").data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }

        let firstStore = makeStore(notifier: MockNotifier(), defaults: defaults)
        await firstStore.refresh()
        firstStore.markRead(friendId: annaId)

        let secondStore = makeStore(notifier: MockNotifier(), defaults: defaults)
        await secondStore.refresh()

        XCTAssertFalse(secondStore.hasUnread(friendId: annaId))
    }
}

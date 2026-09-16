import Foundation
@testable import Geomap

@MainActor
final class MockChatSocket: ChatSocketProtocol {
    private(set) var connectedToken: String?
    private(set) var sentMessages: [(recipientId: UUID, content: String)] = []
    private(set) var disconnectCalled = false
    private var onEvent: (@MainActor (ChatSocketEvent) -> Void)?

    func connect(token: String, onEvent: @escaping @MainActor (ChatSocketEvent) -> Void) {
        connectedToken = token
        self.onEvent = onEvent
    }

    func send(recipientId: UUID, content: String) {
        sentMessages.append((recipientId, content))
    }

    func disconnect() {
        disconnectCalled = true
    }

    /// Simulates an incoming frame, as if the server had pushed it.
    func emit(_ event: ChatSocketEvent) {
        onEvent?(event)
    }
}

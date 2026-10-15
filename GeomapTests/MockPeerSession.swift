import Foundation
@testable import Geomap

@MainActor
final class MockPeerSession: PeerSessionProtocol {
    private(set) var sent: [PeerMessage] = []
    private(set) var isStarted = false
    private var onEvent: (@MainActor (PeerEvent) -> Void)?

    func start(onEvent: @escaping @MainActor (PeerEvent) -> Void) {
        isStarted = true
        self.onEvent = onEvent
    }

    func send(_ message: PeerMessage) { sent.append(message) }

    func stop() {
        isStarted = false
        onEvent = nil
    }

    func emit(_ event: PeerEvent) { onEvent?(event) }
}

import Foundation

enum ChatSocketEvent {
    case message(ChatMessageResponse)
    case error(String)
    case disconnected
}

@MainActor
protocol ChatSocketProtocol: AnyObject {
    // @MainActor on the closure itself (not just the protocol) guarantees
    // to callers that onEvent always fires on the main actor, so they can
    // update UI state directly instead of needing their own Task-hop —
    // which, if added on the caller's side instead, would make event
    // delivery merely *scheduled* rather than synchronous, an easy way to
    // introduce timing bugs (caught by flaky-looking test failures where
    // incoming events hadn't been processed yet by the next assertion).
    func connect(token: String, onEvent: @escaping @MainActor (ChatSocketEvent) -> Void)
    func send(recipientId: UUID, content: String)
    func disconnect()
}

private struct ChatSendFrame: Encodable {
    let type = "message"
    let recipientId: UUID
    let content: String
}

private struct ChatFrameEnvelope: Decodable {
    let type: String
}

private struct ChatErrorFrame: Decodable {
    let message: String
}

/// Plain WebSocket per CHAT_PROTOCOL.md — no STOMP. Auth goes in the `token`
/// query param on the handshake URL (not a header: a WebSocket upgrade
/// can't easily carry a custom Authorization header). One connection per
/// active chat screen; the caller reconnects by calling `connect` again
/// (e.g. on app foreground), matching the protocol's "no server-side
/// session persistence across a dropped connection" note.
@MainActor
final class ChatSocket: ChatSocketProtocol {
    private let baseURL: URL
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?
    private var onEvent: (@MainActor (ChatSocketEvent) -> Void)?

    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = ISO8601DateFormatter.chatWithFractionalSeconds.date(from: string) {
                return date
            }
            if let date = ISO8601DateFormatter.chatStandard.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognized date format: \(string)"
            )
        }
        return decoder
    }()

    init(baseURL: URL = Config.wsBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func connect(token: String, onEvent: @escaping @MainActor (ChatSocketEvent) -> Void) {
        disconnect()
        self.onEvent = onEvent

        var components = URLComponents(
            url: baseURL.appendingPathComponent("/ws/chat"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "token", value: token)]

        let task = session.webSocketTask(with: components.url!)
        self.task = task
        task.resume()
        listen()
    }

    func send(recipientId: UUID, content: String) {
        guard let task else { return }
        let frame = ChatSendFrame(recipientId: recipientId, content: content)
        guard let data = try? encoder.encode(frame), let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }

    func disconnect() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func listen() {
        receiveLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.task else { return }
                do {
                    let message = try await task.receive()
                    self.handle(message)
                } catch {
                    if !Task.isCancelled {
                        self.onEvent?(.disconnected)
                    }
                    return
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let string):
            text = string
        case .data(let data):
            guard let decoded = String(data: data, encoding: .utf8) else { return }
            text = decoded
        @unknown default:
            return
        }

        guard let data = text.data(using: .utf8),
              let envelope = try? decoder.decode(ChatFrameEnvelope.self, from: data) else { return }

        switch envelope.type {
        case "message":
            if let chatMessage = try? decoder.decode(ChatMessageResponse.self, from: data) {
                onEvent?(.message(chatMessage))
            }
        case "error":
            if let errorFrame = try? decoder.decode(ChatErrorFrame.self, from: data) {
                onEvent?(.error(errorFrame.message))
            }
        default:
            break
        }
    }
}

private extension ISO8601DateFormatter {
    static let chatStandard = ISO8601DateFormatter()

    static let chatWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

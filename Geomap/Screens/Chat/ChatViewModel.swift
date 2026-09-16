import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [ChatMessageResponse] = []
    @Published var draftText = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    let friendId: UUID
    let friendDisplayName: String
    let currentUserId: UUID

    private let apiClient: APIClient
    private let socket: ChatSocketProtocol
    private let tokenProvider: () -> String?

    init(
        friendId: UUID,
        friendDisplayName: String,
        currentUserId: UUID,
        apiClient: APIClient = .shared,
        // Not defaulted to ChatSocket() directly: default-argument
        // expressions are evaluated in the caller's context, which isn't
        // provably @MainActor-isolated at every call site (e.g. ChatView's
        // own init) even though ChatViewModel itself is — constructing the
        // real socket in the init body instead, which genuinely does run
        // on the main actor, sidesteps that.
        socket: ChatSocketProtocol? = nil,
        tokenProvider: @escaping () -> String? = { KeychainService.shared.getToken() }
    ) {
        self.friendId = friendId
        self.friendDisplayName = friendDisplayName
        self.currentUserId = currentUserId
        self.apiClient = apiClient
        self.socket = socket ?? ChatSocket()
        self.tokenProvider = tokenProvider
    }

    /// Loads history over REST, then opens the realtime connection for
    /// anything sent while this screen is open. Per CHAT_PROTOCOL.md,
    /// nothing is lost if the socket isn't connected — messages sent while
    /// away are simply picked up next time history is loaded.
    func start() async {
        await loadHistory()
        guard let token = tokenProvider() else {
            errorMessage = "Not signed in."
            return
        }
        socket.connect(token: token) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        socket.disconnect()
    }

    func loadHistory() async {
        isLoading = true
        errorMessage = nil
        do {
            let history = try await apiClient.chatMessages(friendId: friendId)
            messages = history.sorted { $0.sentAt < $1.sentAt }
        } catch let error as APIError {
            errorMessage = error.displayMessage
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
        isLoading = false
    }

    var canSend: Bool {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= 1000
    }

    func send() {
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1000 else { return }

        socket.send(recipientId: friendId, content: trimmed)

        // No ack frame and no echo per CHAT_PROTOCOL.md — append locally
        // so the sender sees their own message immediately.
        let optimisticMessage = ChatMessageResponse(
            id: UUID(),
            senderId: currentUserId,
            recipientId: friendId,
            content: trimmed,
            sentAt: Date(),
            readAt: nil
        )
        messages.append(optimisticMessage)
        draftText = ""
    }

    private func handle(_ event: ChatSocketEvent) {
        switch event {
        case .message(let message):
            guard message.senderId == friendId || message.recipientId == friendId else { return }
            guard !messages.contains(where: { $0.id == message.id }) else { return }
            messages.append(message)
        case .error(let message):
            errorMessage = message
        case .disconnected:
            break
        }
    }
}

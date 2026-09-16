import Foundation

@MainActor
protocol NotificationPosting {
    func postNewMessageNotification(friendDisplayName: String, preview: String)
}

extension LocalNotifier: NotificationPosting {}

/// Tracks which conversations have unread activity, driving the badge on
/// the messages button and per-row indicators in the inbox, and fires a
/// local notification banner when new activity is detected for a
/// conversation the user isn't currently looking at.
///
/// There's no read-receipt endpoint yet (CHAT_PROTOCOL.md: "readAt is not
/// yet settable over this protocol"), so "read" is a purely client-side
/// concept here: the latest moment the user had that conversation open.
@MainActor
final class UnreadMessagesStore: ObservableObject {
    /// The friend whose ChatView is currently on screen, if any — set by
    /// ChatView itself. Polling suppresses notifications for this friend:
    /// without it, sending a message yourself (which also advances that
    /// conversation's lastMessageSentAt) would incorrectly notify you
    /// about your own outgoing message, since the conversations list
    /// doesn't tell us who sent the last message, only when.
    @Published var currentlyOpenFriendId: UUID?

    @Published private(set) var lastMessageAt: [UUID: Date] = [:]
    @Published private(set) var lastReadAt: [UUID: Date] = [:]

    private var lastSeenAt: [UUID: Date] = [:]
    /// The last time *this client* sent a message to each friend — checked
    /// before notifying, since ConversationResponse has no senderId to
    /// distinguish "friend sent me a message" from "I sent one to them"
    /// (both advance lastMessageSentAt identically). currentlyOpenFriendId
    /// alone isn't reliable enough for this: it only covers the exact
    /// window the chat screen is on top, and in practice self-notifications
    /// still slipped through it in testing.
    private var recentlySentAt: [UUID: Date] = [:]
    private var hasCompletedFirstPoll = false
    private var pollingTask: Task<Void, Never>?

    private let apiClient: APIClient
    private let notifier: NotificationPosting
    private let defaults: UserDefaults
    private let lastReadDefaultsKey: String

    init(
        currentUserId: UUID,
        apiClient: APIClient = .shared,
        // Not defaulted to LocalNotifier.shared directly: same reasoning
        // as ChatViewModel's socket parameter — default-argument
        // expressions aren't provably @MainActor at every call site, so
        // the real value is constructed in the init body instead.
        notifier: NotificationPosting? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.apiClient = apiClient
        self.notifier = notifier ?? LocalNotifier.shared
        self.defaults = defaults
        self.lastReadDefaultsKey = "unread.lastReadAt.\(currentUserId.uuidString)"
        loadLastRead()
    }

    func unreadFriendIds() -> Set<UUID> {
        Set(lastMessageAt.compactMap { friendId, sentAt in
            sentAt > (lastReadAt[friendId] ?? .distantPast) ? friendId : nil
        })
    }

    var unreadCount: Int { unreadFriendIds().count }

    func hasUnread(friendId: UUID) -> Bool {
        guard let sentAt = lastMessageAt[friendId] else { return false }
        return sentAt > (lastReadAt[friendId] ?? .distantPast)
    }

    func markRead(friendId: UUID) {
        lastReadAt[friendId] = Date()
        persistLastRead()
    }

    /// Call right when sending a message, so the next poll(s) that observe
    /// that message landing in the conversation list don't mistake it for
    /// an incoming one and notify you about your own text.
    func recordSentMessage(to friendId: UUID) {
        recentlySentAt[friendId] = Date()
    }

    func startPolling(interval: TimeInterval = 15) {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// One fetch-and-compare cycle, exposed separately from the polling
    /// loop so it can be tested without waiting on a timer.
    func refresh() async {
        guard let conversations = try? await apiClient.conversations() else { return }

        for conversation in conversations {
            guard let sentAt = conversation.lastMessageSentAt else { continue }
            lastMessageAt[conversation.friendId] = sentAt

            let previouslySeen = lastSeenAt[conversation.friendId]
            lastSeenAt[conversation.friendId] = sentAt

            let isNewSinceLastPoll = previouslySeen != sentAt
            let isNotTheOpenConversation = conversation.friendId != currentlyOpenFriendId
            let isRecentlySentByMe: Bool = {
                guard let sentByMeAt = recentlySentAt[conversation.friendId] else { return false }
                return abs(sentAt.timeIntervalSince(sentByMeAt)) < 5
            }()
            if hasCompletedFirstPoll, isNewSinceLastPoll, isNotTheOpenConversation, !isRecentlySentByMe {
                notifier.postNewMessageNotification(
                    friendDisplayName: conversation.displayName,
                    preview: conversation.lastMessage ?? "New message"
                )
            }
        }
        hasCompletedFirstPoll = true
    }

    private func persistLastRead() {
        let raw = lastReadAt.mapValues { $0.timeIntervalSince1970 }
        let encoded = Dictionary(uniqueKeysWithValues: raw.map { ($0.key.uuidString, $0.value) })
        defaults.set(encoded, forKey: lastReadDefaultsKey)
    }

    private func loadLastRead() {
        guard let stored = defaults.dictionary(forKey: lastReadDefaultsKey) as? [String: Double] else { return }
        var result: [UUID: Date] = [:]
        for (key, value) in stored {
            guard let id = UUID(uuidString: key) else { continue }
            result[id] = Date(timeIntervalSince1970: value)
        }
        lastReadAt = result
    }
}

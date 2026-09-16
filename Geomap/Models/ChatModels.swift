import Foundation

struct ChatMessageResponse: Decodable, Identifiable, Equatable {
    let id: UUID
    let senderId: UUID
    let recipientId: UUID
    let content: String
    let sentAt: Date
    let readAt: Date?
}

struct ConversationResponse: Decodable, Identifiable {
    let friendId: UUID
    let displayName: String
    let profilePhotoUrl: String?
    /// Not marked required in the contract — a confirmed friend with no
    /// message history yet presumably still appears in the inbox with
    /// these nil, rather than being omitted entirely.
    let lastMessage: String?
    let lastMessageSentAt: Date?

    var id: UUID { friendId }
}

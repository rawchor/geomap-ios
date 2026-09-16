import SwiftUI

struct ConversationsListView: View {
    let currentUserId: UUID

    @StateObject private var viewModel = ConversationsListViewModel()
    @EnvironmentObject private var unreadStore: UnreadMessagesStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.conversations.isEmpty {
                    ProgressView()
                } else if viewModel.conversations.isEmpty {
                    Text("No conversations yet")
                        .foregroundStyle(.secondary)
                } else {
                    List(viewModel.conversations) { conversation in
                        NavigationLink {
                            ChatView(
                                friendId: conversation.friendId,
                                friendDisplayName: conversation.displayName,
                                currentUserId: currentUserId
                            )
                        } label: {
                            conversationRow(conversation)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await viewModel.load()
            }
            .refreshable {
                await viewModel.load()
            }
        }
    }

    private func conversationRow(_ conversation: ConversationResponse) -> some View {
        HStack(spacing: 12) {
            AvatarView(photoURL: conversation.profilePhotoUrl, displayName: conversation.displayName, diameter: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.displayName)
                    .font(.headline)
                Text(conversation.lastMessage ?? "No messages yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if unreadStore.hasUnread(friendId: conversation.friendId) {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.vertical, 4)
    }
}

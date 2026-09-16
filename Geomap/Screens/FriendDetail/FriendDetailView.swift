import SwiftUI

struct FriendDetailView: View {
    let friend: NearbyFriendResponse

    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                AvatarView(
                    photoURL: friend.profilePhotoUrl,
                    displayName: friend.displayName,
                    ringColor: friend.degree.ringColor,
                    diameter: 96
                )

                Text(friend.displayName)
                    .font(.title2.bold())

                Text(connectionContext)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                statusBubble
                    .padding(.top, 4)

                if let currentUserId {
                    NavigationLink {
                        ChatView(friendId: friend.userId, friendDisplayName: friend.displayName, currentUserId: currentUserId)
                    } label: {
                        Label("Message", systemImage: "message.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }

                Spacer()
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }

    private var currentUserId: UUID? {
        if case .loggedIn(let user) = sessionStore.authState {
            return user.id
        }
        return nil
    }

    private var connectionContext: String {
        switch friend.degree {
        case .firstDegree:
            return "Direct friend"
        case .secondDegree:
            if let mutualFriendName = friend.mutualFriendName, !mutualFriendName.isEmpty {
                return "Friends with \(mutualFriendName)"
            }
            return "Friend of a friend"
        }
    }

    @ViewBuilder
    private var statusBubble: some View {
        if let text = friend.status?.displayText {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.15), in: Capsule())
        } else {
            Text("No status set")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

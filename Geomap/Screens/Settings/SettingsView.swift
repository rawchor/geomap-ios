import SwiftUI

struct SettingsView: View {
    let currentUser: User
    let onLogout: () -> Void

    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var unreadStore: UnreadMessagesStore
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingMyStatus = false

    var body: some View {
        NavigationStack {
            List {
                Section("Profile") {
                    HStack(spacing: 12) {
                        AvatarView(photoURL: nil, displayName: currentUser.displayName, ringColor: Palette.maroon, diameter: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentUser.displayName).font(.headline)
                            Text(currentUser.email).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button {
                        isShowingMyStatus = true
                    } label: {
                        Label("Change status", systemImage: "text.bubble")
                    }
                }

                Section("Friends") {
                    friendsContent
                }

                Section {
                    Button(role: .destructive) {
                        dismiss()
                        onLogout()
                    } label: {
                        Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $isShowingMyStatus) {
                MyStatusView()
            }
        }
    }

    @ViewBuilder
    private var friendsContent: some View {
        if !viewModel.hasLoaded {
            ProgressView()
        } else if let errorMessage = viewModel.errorMessage, viewModel.friends.isEmpty {
            Text(errorMessage).foregroundStyle(.secondary)
        } else if viewModel.friends.isEmpty {
            Text("No friends yet").foregroundStyle(.secondary)
        } else {
            ForEach(viewModel.friends) { friend in
                NavigationLink {
                    ChatView(
                        friendId: friend.userId,
                        friendDisplayName: friend.displayName,
                        currentUserId: currentUser.id
                    )
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(photoURL: friend.profilePhotoUrl, displayName: friend.displayName, diameter: 40)
                        Text(friend.displayName)
                        Spacer()
                        if unreadStore.hasUnread(friendId: friend.userId) {
                            Circle().fill(Palette.rust).frame(width: 10, height: 10)
                        }
                    }
                }
            }
        }
    }
}

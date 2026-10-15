import SwiftUI

struct AddFriendView: View {
    @StateObject private var viewModel = AddFriendViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                content
                Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFinished ? "Done" : "Cancel") {
                        Task {
                            await viewModel.cancel()
                            dismiss()
                        }
                    }
                }
            }
            .task { await viewModel.start() }
            .onDisappear { Task { await viewModel.cancel() } }
        }
    }

    private var isFinished: Bool {
        switch viewModel.state {
        case .success, .alreadyFriends: return true
        default: return false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .starting, .lookingUp:
            ProgressView()
        case .searching:
            statusBlock(
                icon: "dot.radiowaves.left.and.right",
                title: "Looking for a friend nearby",
                message: "Hold phones together and ask them to open Add Friend in Settings too."
            ) { ProgressView() }
        case .confirming(let profile):
            profileBlock(profile)
            Text("Add \(profile.displayName) as a friend?")
                .font(.headline)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Cancel") {
                    Task { await viewModel.cancel(); await viewModel.start() }
                }
                .buttonStyle(.bordered)
                Button("Confirm") {
                    Task { await viewModel.confirm() }
                }
                .buttonStyle(.borderedProminent)
            }
        case .waitingForOther(let profile):
            profileBlock(profile)
            Text("Waiting for \(profile.displayName) to confirm…")
                .font(.headline)
                .multilineTextAlignment(.center)
            ProgressView()
        case .success(let profile):
            profileBlock(profile)
            Label("You and \(profile.displayName) are now friends", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Palette.forest)
                .multilineTextAlignment(.center)
        case .alreadyFriends(let profile):
            profileBlock(profile)
            Text("You and \(profile.displayName) are already friends.")
                .font(.headline)
                .multilineTextAlignment(.center)
        case .expired:
            statusBlock(
                icon: "clock.badge.exclamationmark",
                title: "That code expired",
                message: "Try again — both of you may need to reopen Add Friend."
            ) {
                Button("Try again") { Task { await viewModel.retry() } }
                    .buttonStyle(.borderedProminent)
            }
        case .failed(let message):
            statusBlock(icon: "exclamationmark.triangle", title: "Couldn't add friend", message: message) {
                Button("Try again") { Task { await viewModel.retry() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func profileBlock(_ profile: UserProfileResponse) -> some View {
        VStack(spacing: 8) {
            AvatarView(photoURL: profile.profilePhotoUrl, displayName: profile.displayName, diameter: 96)
            Text(profile.displayName).font(.title2.bold())
        }
    }

    private func statusBlock<Accessory: View>(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            accessory()
        }
    }
}

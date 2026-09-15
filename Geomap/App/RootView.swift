import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sessionStore: SessionStore

    var body: some View {
        switch sessionStore.authState {
        case .loading:
            ProgressView()
        case .loggedOut:
            LoginView()
        case .loggedIn(let user):
            // Placeholder until the Map screen lands.
            SignedInPlaceholderView(user: user)
        }
    }
}

private struct SignedInPlaceholderView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    let user: User

    var body: some View {
        VStack(spacing: 16) {
            Text("Signed in as \(user.displayName)")
                .font(.headline)
            Button("Log Out") {
                sessionStore.logout()
            }
        }
    }
}

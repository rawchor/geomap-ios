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
            MapView(currentUser: user)
        }
    }
}

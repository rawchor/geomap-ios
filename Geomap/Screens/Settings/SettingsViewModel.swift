import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published private(set) var friends: [FriendResponse] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            friends = try await apiClient.friends()
        } catch let error as APIError {
            errorMessage = error.displayMessage
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
        isLoading = false
        hasLoaded = true
    }
}

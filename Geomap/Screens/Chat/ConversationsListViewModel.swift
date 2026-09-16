import Foundation

@MainActor
final class ConversationsListViewModel: ObservableObject {
    @Published private(set) var conversations: [ConversationResponse] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let apiClient: APIClient

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            conversations = try await apiClient.conversations()
        } catch let error as APIError {
            errorMessage = error.displayMessage
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
        isLoading = false
    }
}

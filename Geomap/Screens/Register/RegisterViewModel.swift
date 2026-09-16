import Foundation

@MainActor
final class RegisterViewModel: ObservableObject {
    @Published var displayName = ""
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?

    /// Matches RegisterRequest's password minLength (8) in API_CONTRACT.json
    /// — client-side gating for early feedback; the backend still enforces
    /// this and any other validation on submit.
    var canSubmit: Bool {
        !email.isEmpty && password.count >= 8 && !isSubmitting
    }

    func submit(using sessionStore: SessionStore) async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await sessionStore.register(displayName: displayName, email: email, password: password)
        } catch let error as APIError {
            errorMessage = error.displayMessage
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
        isSubmitting = false
    }
}

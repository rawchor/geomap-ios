import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?

    var canSubmit: Bool {
        !email.isEmpty && !password.isEmpty && !isSubmitting
    }

    func submit(using sessionStore: SessionStore) async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        do {
            try await sessionStore.login(email: email, password: password)
        } catch let error as APIError {
            errorMessage = error.displayMessage
        } catch {
            errorMessage = "Something went wrong. Please try again."
        }
        isSubmitting = false
    }
}

import SwiftUI

private enum RegisterField: Hashable {
    case displayName, email, password
}

struct RegisterView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = RegisterViewModel()
    @FocusState private var focusedField: RegisterField?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Account")
                .font(.largeTitle.bold())

            VStack(spacing: 16) {
                TextField("Display Name", text: $viewModel.displayName)
                    .textContentType(.name)
                    .textFieldRowStyle()
                    .focused($focusedField, equals: .displayName)
                    .onTapGesture { focusedField = .displayName }

                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldRowStyle()
                    .focused($focusedField, equals: .email)
                    .onTapGesture { focusedField = .email }

                SecureField("Password (min. 8 characters)", text: $viewModel.password)
                    .textContentType(.newPassword)
                    .textFieldRowStyle()
                    .focused($focusedField, equals: .password)
                    .onTapGesture { focusedField = .password }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await viewModel.submit(using: sessionStore) }
            } label: {
                if viewModel.isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Register")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmit)

            Button("Already have an account? Log In") {
                dismiss()
            }
            .font(.footnote)
        }
        .padding(24)
    }
}

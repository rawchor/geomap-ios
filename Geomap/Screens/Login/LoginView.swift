import SwiftUI

private enum LoginField: Hashable {
    case email, password
}

struct LoginView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = LoginViewModel()
    @FocusState private var focusedField: LoginField?

    var body: some View {
        VStack(spacing: 20) {
            Text("Geomap")
                .font(.largeTitle.bold())

            VStack(spacing: 16) {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldRowStyle()
                    .focused($focusedField, equals: .email)
                    // Redundant with the field's native tap-to-focus, but
                    // that path has been unreliable under automated touch
                    // injection (Simulator UI-testing tools); this backs
                    // it with a plain tap gesture driving @FocusState
                    // explicitly, using the same simple mechanism that's
                    // proven reliable for buttons elsewhere in the app.
                    .onTapGesture { focusedField = .email }

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
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
                    Text("Log In")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSubmit)
        }
        .padding(24)
    }
}

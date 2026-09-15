import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @StateObject private var viewModel = LoginViewModel()

    var body: some View {
        VStack(spacing: 20) {
            Text("Geomap")
                .font(.largeTitle.bold())

            VStack(spacing: 12) {
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                SecureField("Password", text: $viewModel.password)
                    .textContentType(.password)
                    .textFieldStyle(.roundedBorder)
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

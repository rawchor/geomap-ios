import SwiftUI

struct MyStatusView: View {
    @StateObject private var viewModel = MyStatusViewModel()
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("My Status")
                    .font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
            }

            currentStatusBubble

            TextField("Search or type a status...", text: $viewModel.searchText)
                .textFieldRowStyle()
                .focused($searchFieldFocused)
                .onTapGesture { searchFieldFocused = true }
                .onSubmit {
                    Task { await viewModel.saveCustomText() }
                }

            Picker("Expires", selection: $viewModel.selectedExpiry) {
                ForEach(StatusExpiry.allCases) { expiry in
                    Text(expiry.label).tag(expiry)
                }
            }
            .pickerStyle(.segmented)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if viewModel.canSaveAsCustomText {
                        Button {
                            Task { await viewModel.saveCustomText() }
                        } label: {
                            Label("Use \"\(viewModel.searchText)\" as your status", systemImage: "text.bubble")
                        }
                    }

                    ForEach(viewModel.filteredPresets) { preset in
                        Button {
                            Task { await viewModel.selectPreset(preset) }
                        } label: {
                            HStack {
                                Text(preset.emoji)
                                Text(preset.label)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }

            if viewModel.currentStatus?.displayText != nil {
                Button("Clear Status", role: .destructive) {
                    Task { await viewModel.clearStatus() }
                }
            }
        }
        .padding(24)
        .disabled(viewModel.isSaving)
        .task {
            await viewModel.loadInitialData()
        }
    }

    @ViewBuilder
    private var currentStatusBubble: some View {
        if let text = viewModel.currentStatus?.displayText {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.15), in: Capsule())
        } else {
            Text("No status set")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var draftFocused: Bool

    init(friendId: UUID, friendDisplayName: String, currentUserId: UUID) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(
            friendId: friendId,
            friendDisplayName: friendDisplayName,
            currentUserId: currentUserId
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(8)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    guard let lastId = viewModel.messages.last?.id else { return }
                    withAnimation {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }

            if viewModel.isLoading && viewModel.messages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            }

            HStack(spacing: 8) {
                TextField("Message", text: $viewModel.draftText, axis: .vertical)
                    .textFieldRowStyle()
                    .focused($draftFocused)
                    .onTapGesture { draftFocused = true }
                    .lineLimit(1...4)

                Button {
                    viewModel.send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(!viewModel.canSend)
            }
            .padding(12)
        }
        .navigationTitle(viewModel.friendDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.start()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessageResponse) -> some View {
        let isMine = message.senderId == viewModel.currentUserId
        HStack {
            if isMine { Spacer(minLength: 40) }
            Text(message.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isMine ? Color.blue.opacity(0.85) : Color(.systemGray5), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(isMine ? .white : .primary)
            if !isMine { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }
}

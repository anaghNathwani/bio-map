import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    struct Message: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        var text: String
        var isError = false
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var isResponding = false
    /// Set when we're on the limited fallback engine, explaining why.
    let limitationNote: String?

    private let engine: AssistantEngine
    private var responseTask: Task<Void, Never>?

    init() {
        let made = AssistantFactory.make()
        engine = made.engine
        limitationNote = made.note
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }

        messages.append(Message(role: .user, text: text))
        messages.append(Message(role: .assistant, text: ""))
        let replyIndex = messages.count - 1
        isResponding = true

        responseTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await snapshot in self.engine.reply(to: text) {
                    self.messages[replyIndex].text = snapshot
                }
                if self.messages[replyIndex].text.isEmpty {
                    self.messages[replyIndex].text = "I didn't have an answer for that — could you rephrase it?"
                }
            } catch is CancellationError {
                // cleared or dismissed mid-answer
            } catch {
                self.messages[replyIndex].text = (error as? AssistantError)?.errorDescription
                    ?? "Sorry, something went wrong answering that. Please try again."
                self.messages[replyIndex].isError = true
            }
            self.isResponding = false
        }
    }

    func clear() {
        responseTask?.cancel()
        responseTask = nil
        engine.reset()
        messages = []
        isResponding = false
    }
}

struct ChatView: View {
    @ObservedObject var vm: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private let suggestions = [
        "How do I report a bird?",
        "How can I tell a sparrow from a finch?",
        "What does the bookmark do?",
        "What should I feed backyard birds?",
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let note = vm.limitationNote {
                    Label(note, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if vm.messages.isEmpty { emptyState }
                            ForEach(vm.messages) { message in
                                bubble(message).id(message.id)
                            }
                        }
                        .padding()
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: vm.messages.last?.text) { _, _ in
                        if let last = vm.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }

                inputBar
            }
            .navigationTitle("BirdMap Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", role: .destructive) { vm.clear() }
                        .disabled(vm.messages.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bird.fill")
                .font(.system(size: 38))
                .foregroundStyle(Color.teal)
            Text("Ask me anything about birds or BirdMap")
                .font(.headline)
            Text("I run entirely on this phone — nothing you type leaves it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        vm.send(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(Color.teal)
                    }
                }
            }
        }
        .padding(.top, 30)
    }

    @ViewBuilder
    private func bubble(_ message: ChatViewModel.Message) -> some View {
        let isUser = message.role == .user
        HStack {
            if isUser { Spacer(minLength: 40) }
            Group {
                if message.text.isEmpty {
                    ProgressView().padding(.vertical, 4)
                } else {
                    Text(message.text)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .foregroundStyle(isUser ? .white : (message.isError ? Color.orange : .primary))
            .background(
                isUser ? Color.teal : Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .textSelection(.enabled)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask a question…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                .submitLabel(.send)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.teal : Color.gray.opacity(0.4))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        !vm.isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        vm.send(draft)
        draft = ""
    }
}

/// The small dot floating in the bottom-right corner that opens the assistant.
/// The dot itself is tiny; the padding around it is just a comfortable tap target.
struct AssistantDot: View {
    @StateObject private var vm = ChatViewModel()
    @State private var showChat = false

    var body: some View {
        Button {
            showChat = true
        } label: {
            Circle()
                .fill(Color.teal.gradient)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .padding(15)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ask BirdMap Assistant")
        .sheet(isPresented: $showChat) {
            ChatView(vm: vm)
                .presentationDetents([.large])
        }
    }
}

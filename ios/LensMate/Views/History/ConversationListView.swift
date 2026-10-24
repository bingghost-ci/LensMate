// LensMate - ConversationListView.swift
// List of past conversations with search and delete

import SwiftUI

struct ConversationListView: View {
    // MARK: - Environment

    @EnvironmentObject var settingsManager: SettingsManager

    // The single source of truth. The old version kept a local @State copy that was never
    // even populated — History was permanently empty.
    @ObservedObject private var conversationManager = ConversationManager.shared

    // MARK: - State

    @State private var searchText: String = ""

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if conversationManager.conversations.isEmpty {
                    emptyState
                } else {
                    conversationList
                }
            }
            .localizedNavigationTitle("History")
            .searchable(text: $searchText, prompt: "Search conversations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Fresh conversation: next exchange starts a new History entry with
                        // no carried-over model context.
                        conversationManager.startNewConversation()
                        ConversationContext.shared.clear()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No conversations yet")
                .font(.headline)

            Text("Start a conversation with the AI assistant to see your history here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                NavigationLink {
                    ConversationDetailView(conversation: conversation)
                } label: {
                    ConversationRow(conversation: conversation)
                }
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.plain)
    }

    // MARK: - Filtered Conversations

    private var filteredConversations: [Conversation] {
        conversationManager.search(searchText)
    }

    // MARK: - Methods

    private func deleteConversations(at offsets: IndexSet) {
        // Resolve against the FILTERED list (offsets come from it), then delete via the
        // manager so the removal persists.
        let targets = offsets.map { filteredConversations[$0] }
        for conversation in targets {
            conversationManager.deleteConversation(conversation)
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    @Environment(\.locale) private var locale
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                (conversation.messages.isEmpty && conversation.title == "New Conversation" ? Text("New Conversation") : Text(verbatim: conversation.title))
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Text(conversation.lastActivityAt.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(locale)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let lastMessage = conversation.messages.last {
                Text(lastMessage.content)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack {
                Label("\(conversation.messages.count)", systemImage: "bubble.left")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if conversation.hasPhotos {
                    Label("", systemImage: "photo")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Conversation Detail View

struct ConversationDetailView: View {
    @Environment(\.locale) private var locale
    let conversation: Conversation
    @State private var resumed = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(conversation.messages) { message in
                    MessageBubble(message: message)
                }
            }
            .padding()
        }
        .navigationTitle(conversation.messages.isEmpty && conversation.title == "New Conversation" ? L10n.text("New Conversation", locale: locale) : conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Continue this conversation: make it current (new messages append to it)
                    // and reload its recent exchanges as the model's live context, so the next
                    // "Ok LensMate" follow-up picks up where it left off.
                    ConversationManager.shared.resumeConversation(conversation)
                    ConversationContext.shared.seed(from: conversation)
                    resumed = true
                } label: {
                    Label(resumed ? LocalizedStringKey("Resumed") : LocalizedStringKey("Continue"), systemImage: resumed ? "checkmark.circle" : "arrow.right.circle")
                }
                .disabled(resumed)
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    @Environment(\.locale) private var locale
    let message: Message

    var body: some View {
        HStack {
            // User on the right, assistant on the left — same as the live transcript.
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == .user ? AnyShapeStyle(Theme.buttonGradient) : AnyShapeStyle(Color(.systemGray5)))
                    .foregroundColor(message.role == .user ? Color.black.opacity(0.9) : .primary)
                    .cornerRadius(16)

                Text(message.timestamp.formatted(.dateTime.hour().minute().locale(locale)))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if message.role == .assistant {
                Spacer(minLength: 40)
            }
        }
    }
}

#Preview {
    ConversationListView()
        .environmentObject(SettingsManager.shared)
}

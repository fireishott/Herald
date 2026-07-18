import SwiftUI

struct ChatView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    let session: WatchSession
    @State private var replyText = ""
    @State private var isDictating = false

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(session.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .onChange(of: session.messages.count) {
                    if let last = session.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Reply input
            HStack(spacing: 8) {
                TextField("Reply…", text: $replyText)
                    .font(.caption)
                    .textFieldStyle(.plain)

                Button {
                    sendReply()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(replyText.isEmpty ? .gray : Color(hex: "FFBF00"))
                }
                .disabled(replyText.isEmpty)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(hex: "2D2D2B"))
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        connectivity.sendMessage(text, to: session.id)
        replyText = ""
    }
}

struct MessageBubble: View {
    let message: WatchMessage

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 24) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(message.isUser ? Color(hex: "FFBF00") : Color.gray.opacity(0.3))
                    .foregroundStyle(message.isUser ? .black : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if !message.isUser { Spacer(minLength: 24) }
        }
    }
}

#Preview {
    ChatView(session: WatchSession(
        id: "preview",
        title: "Preview Session",
        preview: "Hello there",
        date: Date(),
        messages: [
            WatchMessage(id: "1", content: "Hey, how are you?", isUser: true, date: Date()),
            WatchMessage(id: "2", content: "I am doing well, thanks!", isUser: false, date: Date())
        ]
    ))
    .environmentObject(WatchConnectivityManager.shared)
}

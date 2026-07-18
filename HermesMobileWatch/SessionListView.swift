import SwiftUI

struct SessionListView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @Binding var selectedSession: WatchSession?

    var body: some View {
        Group {
            if connectivity.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title2)
                        .foregroundStyle(Color(hex: "FFBF00"))
                    Text("No Sessions")
                        .font(.headline)
                    Text("Open Hermes on your iPhone to start a conversation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List(connectivity.sessions) { session in
                    Button {
                        selectedSession = session
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.headline)
                                .lineLimit(1)
                            Text(session.preview)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(session.date, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(Color(hex: "FFBF00"))
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.carousel)
            }
        }
        .onAppear {
            connectivity.requestSessions()
        }
    }
}

#Preview {
    @Previewable @State var selected: WatchSession?
    SessionListView(selectedSession: $selected)
        .environmentObject(WatchConnectivityManager.shared)
}

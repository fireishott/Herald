import SwiftUI

struct ContentView: View {
    @EnvironmentObject var connectivity: WatchConnectivityManager
    @State private var selectedSession: WatchSession?

    var body: some View {
        NavigationStack {
            SessionListView(selectedSession: $selectedSession)
                .navigationTitle("Hermes")
                .navigationDestination(item: $selectedSession) { session in
                    ChatView(session: session)
                }
        }
        .tint(Color(hex: "FFBF00"))
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchConnectivityManager.shared)
}

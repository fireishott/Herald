import Foundation
import WatchConnectivity
import Combine

// MARK: - Models

struct WatchSession: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let preview: String
    let date: Date
    var messages: [WatchMessage]

    static func == (lhs: WatchSession, rhs: WatchSession) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct WatchMessage: Identifiable, Codable {
    let id: String
    let content: String
    let isUser: Bool
    let date: Date
}

// MARK: - Manager

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    @Published var sessions: [WatchSession] = []
    @Published var isReachable = false

    private var wcSession: WCSession?

    override private init() {
        super.init()
        if WCSession.isSupported() {
            let s = WCSession.default
            s.delegate = self
            s.activate()
            self.wcSession = s
        }
    }

    func requestSessions() {
        guard let s = wcSession, s.isReachable else { return }
        s.sendMessage(["action": "requestSessions"], replyHandler: { reply in
            Task { @MainActor in
                WatchConnectivityManager.shared.handleSessionsReply(reply)
            }
        }, errorHandler: { error in
            print("[Watch] Error requesting sessions: \(error.localizedDescription)")
        })
    }

    func sendMessage(_ text: String, to sessionId: String) {
        guard let s = wcSession, s.isReachable else { return }

        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            let msg = WatchMessage(
                id: UUID().uuidString,
                content: text,
                isUser: true,
                date: Date()
            )
            sessions[index].messages.append(msg)
        }

        s.sendMessage([
            "action": "sendMessage",
            "sessionId": sessionId,
            "text": text
        ], replyHandler: { reply in
            Task { @MainActor in
                if let response = reply["response"] as? String,
                   let index = WatchConnectivityManager.shared.sessions.firstIndex(where: { $0.id == sessionId }) {
                    let msg = WatchMessage(
                        id: UUID().uuidString,
                        content: response,
                        isUser: false,
                        date: Date()
                    )
                    WatchConnectivityManager.shared.sessions[index].messages.append(msg)
                }
            }
        }, errorHandler: { error in
            print("[Watch] Error sending message: \(error.localizedDescription)")
        })
    }

    private func handleSessionsReply(_ reply: [String: Any]) {
        guard let data = reply["sessions"] as? Data else { return }
        do {
            let decoded = try JSONDecoder().decode([WatchSession].self, from: data)
            self.sessions = decoded
        } catch {
            print("[Watch] Failed to decode sessions: \(error)")
        }
    }

    func updateSessionsFromData(_ data: Data) {
        do {
            let decoded = try JSONDecoder().decode([WatchSession].self, from: data)
            self.sessions = decoded
        } catch {
            print("[Watch] Failed to decode sessions: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: @preconcurrency WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in
            WatchConnectivityManager.shared.isReachable = reachable
        }
        if let error = error {
            print("[Watch] WC activation error: \(error.localizedDescription)")
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            WatchConnectivityManager.shared.isReachable = reachable
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        nonisolated(unsafe) let ctx = applicationContext
        Task { @MainActor in
            if let data = ctx["sessions"] as? Data {
                WatchConnectivityManager.shared.updateSessionsFromData(data)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        nonisolated(unsafe) let msg = message
        Task { @MainActor in
            if let data = msg["sessions"] as? Data {
                WatchConnectivityManager.shared.updateSessionsFromData(data)
            }
        }
    }
}

// MARK: - Color Helper

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

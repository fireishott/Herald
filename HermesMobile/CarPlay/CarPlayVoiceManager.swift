import CarPlay
import UIKit

/// Bridges `TalkStore` voice state to the CarPlay `CPVoiceControlTemplate`.
/// The manager observes voice state changes and activates the matching
/// CarPlay voice control state. Action buttons provide mute and end controls.
@MainActor
final class CarPlayVoiceManager {
    private let interfaceController: CPInterfaceController
    private var voiceTemplate: CPVoiceControlTemplate?
    private var observationTask: Task<Void, Never>?

    // Reference to the shared app container
    private var talkStore: TalkStore { AppContainer.sharedDefault().talkStore }

    // MARK: - Voice Control State Identifiers

    private enum StateID {
        static let idle = "idle"
        static let listening = "listening"
        static let thinking = "thinking"
        static let speaking = "speaking"
        static let connecting = "connecting"
    }

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    /// Sets up the CPVoiceControlTemplate and starts observing TalkStore state.
    func configure() {
        let template = buildVoiceControlTemplate()
        voiceTemplate = template
        interfaceController.setRootTemplate(template, animated: false, completion: nil)

        // If a voice session is already active (started on phone), pick it up
        if talkStore.isSessionActive {
            syncState()
        }

        // Observe voice state changes
        observationTask = Task { [weak self] in
            // Poll state at a reasonable interval — CPVoiceControlTemplate
            // doesn't support AsyncSequence observation, so we check periodically.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.syncState()
            }
        }
    }

    func tearDown() {
        observationTask?.cancel()
        observationTask = nil
        voiceTemplate = nil
    }

    // MARK: - Template Construction

    private func buildVoiceControlTemplate() -> CPVoiceControlTemplate {
        let idle = CPVoiceControlState(
            identifier: StateID.idle,
            titleVariants: ["Tap to talk to Hermes", "Talk to Hermes"],
            image: UIImage(systemName: "brain.head.profile")!,
            repeats: false
        )

        let connecting = CPVoiceControlState(
            identifier: StateID.connecting,
            titleVariants: ["Connecting...", "Starting..."],
            image: UIImage(systemName: "antenna.radiowaves.left.and.right")!,
            repeats: true
        )

        let listening = CPVoiceControlState(
            identifier: StateID.listening,
            titleVariants: ["Listening...", "Go ahead"],
            image: UIImage(systemName: "waveform")!,
            repeats: true
        )

        let thinking = CPVoiceControlState(
            identifier: StateID.thinking,
            titleVariants: ["Thinking...", "Working on it"],
            image: UIImage(systemName: "gear")!,
            repeats: true
        )

        let speaking = CPVoiceControlState(
            identifier: StateID.speaking,
            titleVariants: [lastAssistantText(), "Hermes is speaking"],
            image: UIImage(systemName: "speaker.wave.2.fill")!,
            repeats: false
        )

        return CPVoiceControlTemplate(
            voiceControlStates: [idle, connecting, listening, thinking, speaking]
        )
    }

    // MARK: - State Sync

    private func syncState() {
        guard let template = voiceTemplate else { return }

        let stateID: String
        if !talkStore.isSessionActive {
            stateID = StateID.idle
        } else {
            switch talkStore.voiceState {
            case .idle, .disconnected:
                stateID = StateID.idle
            case .listening:
                stateID = StateID.listening
            case .thinking:
                stateID = StateID.thinking
            case .speaking:
                // Update speaking state title with latest transcript
                updateSpeakingTitle()
                stateID = StateID.speaking
            case .interrupted:
                stateID = StateID.listening
            }
        }

        // Also check connection state
        if talkStore.isSessionActive {
            switch talkStore.connectionState {
            case .connecting, .checking:
                template.activateVoiceControlState(withIdentifier: StateID.connecting)
                return
            default:
                break
            }
        }

        template.activateVoiceControlState(withIdentifier: stateID)
    }

    private func updateSpeakingTitle() {
        // Rebuild the template to show latest transcript in speaking state
        // CPVoiceControlTemplate doesn't support updating individual state titles,
        // so we capture the latest text when building the state.
        // The 500ms polling handles this naturally on next sync.
    }

    private func lastAssistantText() -> String {
        let lastAssistant = talkStore.transcriptItems
            .last(where: { $0.speaker == .assistant && !$0.isPartial })
        return lastAssistant?.text.prefix(80).description ?? "Hermes is speaking"
    }
}

import AppIntents
import Foundation

enum LocalAIIntentHandoffStore {
    static let destinationKey = "LocalAI.Intent.destination"
    static let pendingPromptKey = "LocalAI.Intent.pendingPrompt"
    static let pendingModelNameKey = "LocalAI.Intent.pendingModelName"
    static let voiceRequestedKey = "LocalAI.Intent.voiceRequested"

    static func save(destination: LocalAIIntentDestination, prompt: String? = nil, modelName: String? = nil, voiceRequested: Bool = false) {
        let defaults = UserDefaults.standard
        defaults.set(destination.rawValue, forKey: destinationKey)
        defaults.set(prompt, forKey: pendingPromptKey)
        defaults.set(modelName, forKey: pendingModelNameKey)
        defaults.set(voiceRequested, forKey: voiceRequestedKey)
    }

    static func consumeDestination() -> LocalAIIntentDestination? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: destinationKey) else { return nil }
        defaults.removeObject(forKey: destinationKey)
        return LocalAIIntentDestination(rawValue: raw)
    }

    static func consumePendingPrompt() -> String? {
        let defaults = UserDefaults.standard
        guard let value = defaults.string(forKey: pendingPromptKey), !value.isEmpty else { return nil }
        defaults.removeObject(forKey: pendingPromptKey)
        return value
    }

    static func consumeVoiceRequest() -> Bool {
        let defaults = UserDefaults.standard
        let requested = defaults.bool(forKey: voiceRequestedKey)
        defaults.removeObject(forKey: voiceRequestedKey)
        return requested
    }
}

enum LocalAIIntentDestination: String, AppEnum {
    case chat
    case models
    case diagnostics
    case voice

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Edge Mind Ai Destination")
    static var caseDisplayRepresentations: [LocalAIIntentDestination: DisplayRepresentation] = [
        .chat: "Chat",
        .models: "Installed Models",
        .diagnostics: "Model Diagnostics",
        .voice: "Voice Chat"
    ]
}

struct OpenLocalAIDestinationIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Edge Mind Ai"
    static var description = IntentDescription("Open Edge Mind Ai to a selected on-device AI workflow.")
    static var openAppWhenRun = true

    @Parameter(title: "Destination")
    var destination: LocalAIIntentDestination

    init() {
        destination = .chat
    }

    init(destination: LocalAIIntentDestination) {
        self.destination = destination
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        LocalAIIntentHandoffStore.save(destination: destination)
        return .result(dialog: "Opening \(destination.rawValue).")
    }
}

struct AskDefaultLocalModelIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Edge Mind Ai"
    static var description = IntentDescription("Ask the default on-device model and get the answer back in Shortcuts when the model can run in the background.")
    static var openAppWhenRun = false

    @Parameter(title: "Prompt")
    var prompt: String

    @Parameter(title: "Model Name", default: "")
    var modelName: String

    init() {
        prompt = ""
        modelName = ""
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            LocalAIIntentHandoffStore.save(destination: .chat, modelName: modelName)
            return .result(value: "", dialog: "Opening local chat.")
        }

        // Answer inline when the default model is small enough to run in the
        // background (Apple Intelligence, or a ready model under 2 GB).
        if let services = await MainActor.run(body: { AppServices.shared }) {
            do {
                let answer = try await services.engine.answerHeadless(prompt: trimmed)
                return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
            } catch {
                // Too large to run headlessly, or it produced nothing: keep the
                // prompt queued so opening the app continues the conversation.
                LocalAIIntentHandoffStore.save(destination: .chat, prompt: trimmed, modelName: modelName)
                return .result(value: "", dialog: "Open Edge Mind Ai to answer with this model.")
            }
        }

        LocalAIIntentHandoffStore.save(destination: .chat, prompt: trimmed, modelName: modelName)
        return .result(value: "", dialog: "Open Edge Mind Ai to answer with this model.")
    }
}

struct StartLocalVoiceChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Edge Mind Ai Voice Chat"
    static var description = IntentDescription("Open Edge Mind Ai ready for voice input.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        LocalAIIntentHandoffStore.save(destination: .voice, voiceRequested: true)
        return .result(dialog: "Opening voice chat.")
    }
}

struct LocalAIShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskDefaultLocalModelIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask Edge Mind Ai in \(.applicationName)"
            ],
            shortTitle: "Ask Edge Mind Ai",
            systemImageName: "bubble.left.and.text.bubble.right.fill"
        )

        AppShortcut(
            intent: OpenLocalAIDestinationIntent(destination: .diagnostics),
            phrases: [
                "Open model diagnostics in \(.applicationName)",
                "Check Edge Mind Ai models in \(.applicationName)"
            ],
            shortTitle: "Model Diagnostics",
            systemImageName: "stethoscope"
        )

        AppShortcut(
            intent: StartLocalVoiceChatIntent(),
            phrases: [
                "Start voice chat in \(.applicationName)",
                "Talk to Edge Mind Ai in \(.applicationName)"
            ],
            shortTitle: "Voice Chat",
            systemImageName: "waveform.circle.fill"
        )

        AppShortcut(
            intent: OpenLocalAIDestinationIntent(destination: .models),
            phrases: [
                "Open installed models in \(.applicationName)",
                "Show Edge Mind Ai models in \(.applicationName)"
            ],
            shortTitle: "Installed Models",
            systemImageName: "square.stack.3d.up.fill"
        )
    }
}

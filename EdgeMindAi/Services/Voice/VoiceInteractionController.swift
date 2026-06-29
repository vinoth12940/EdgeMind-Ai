import AVFoundation
import Combine
import Speech

@MainActor
final class VoiceInteractionController: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var isSpeaking = false
    @Published var lastError: String?

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: .autoupdatingCurrent) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }()
    private var seedText = ""

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggleListening(seedText: String) async {
        if isListening {
            stopListening()
            return
        }

        guard await requestPermissions() else { return }

        do {
            try startListening(seedText: seedText)
        } catch {
            lastError = error.localizedDescription
            stopListening()
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        deactivateAudioSession()
    }

    func speak(_ text: String, using settings: AppSettings) {
        let spokenText = sanitizedSpeechText(from: text)
        guard !spokenText.isEmpty else { return }

        stopListening()
        lastError = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = error.localizedDescription
        }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: spokenText)
        utterance.voice = preferredVoice(for: settings.voicePreset)
        utterance.rate = utteranceRate(for: settings.voiceResponseRate)
        utterance.pitchMultiplier = pitchMultiplier(for: settings.voicePreset)
        utterance.prefersAssistiveTechnologySettings = true
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        deactivateAudioSession()
    }

    private func requestPermissions() async -> Bool {
        lastError = nil

        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechAuthorized == .authorized else {
            lastError = "Speech recognition permission is required for voice input."
            return false
        }

        let microphoneGranted = await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }

        guard microphoneGranted else {
            lastError = "Microphone permission is required for voice input."
            return false
        }

        return true
    }

    private func startListening(seedText: String) throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw NSError(domain: "VoiceInteractionController", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition is not available right now."])
        }

        stopSpeaking()
        lastError = nil
        self.seedText = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = self.seedText

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                if let result {
                    self.transcript = self.combinedTranscript(dictatedText: result.bestTranscription.formattedString)
                    if result.isFinal {
                        self.stopListening()
                    }
                }

                if let error {
                    let nsError = error as NSError
                    if nsError.code != 216 {
                        self.lastError = error.localizedDescription
                    }
                    self.stopListening()
                }
            }
        }
    }

    private func combinedTranscript(dictatedText: String) -> String {
        let cleanedDictation = dictatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !seedText.isEmpty else {
            return cleanedDictation
        }
        guard !cleanedDictation.isEmpty else {
            return seedText
        }
        return seedText + " " + cleanedDictation
    }

    private func preferredVoice(for preset: AppSettings.VoicePreset) -> AVSpeechSynthesisVoice? {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }

        switch preset {
        case .warm:
            return englishVoices.first(where: { $0.quality == .enhanced && $0.gender == .female })
                ?? englishVoices.first(where: { $0.gender == .female })
                ?? AVSpeechSynthesisVoice(language: "en-US")
        case .clear:
            return englishVoices.first(where: { $0.quality == .enhanced && $0.gender == .male })
                ?? englishVoices.first(where: { $0.gender == .male })
                ?? AVSpeechSynthesisVoice(language: "en-US")
        case .energetic:
            return englishVoices.first(where: { $0.quality == .premium })
                ?? englishVoices.first(where: { $0.quality == .enhanced })
                ?? AVSpeechSynthesisVoice(language: "en-US")
        case .balanced:
            return englishVoices.first(where: { $0.quality == .enhanced })
                ?? AVSpeechSynthesisVoice(language: "en-US")
        }
    }

    private func utteranceRate(for speed: Double) -> Float {
        let normalized = min(max((speed - 0.8) / 0.45, 0), 1)
        return Float(0.43 + (0.12 * normalized))
    }

    private func pitchMultiplier(for preset: AppSettings.VoicePreset) -> Float {
        switch preset {
        case .balanced:
            return 1.0
        case .warm:
            return 0.92
        case .clear:
            return 1.02
        case .energetic:
            return 1.08
        }
    }

    private func sanitizedSpeechText(from text: String) -> String {
        text
            .replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
            .replacingOccurrences(of: "`([^`]*)`", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\[[0-9]+\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Best effort cleanup.
        }
    }
}

extension VoiceInteractionController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.deactivateAudioSession()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isSpeaking = false
            self.deactivateAudioSession()
        }
    }
}

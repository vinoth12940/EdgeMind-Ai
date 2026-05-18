import Foundation

enum ResponsibleAIGuard {
    struct Decision: Equatable {
        let isBlocked: Bool
        let reason: String?
        let response: String?

        static let allowed = Decision(isBlocked: false, reason: nil, response: nil)

        static func blocked(reason: String) -> Decision {
            Decision(
                isBlocked: true,
                reason: reason,
                response: "I cannot help with instructions that could cause harm. I can help with safety, prevention, legal alternatives, or a high-level explanation instead."
            )
        }
    }

    static func evaluate(prompt: String) -> Decision {
        let normalized = normalize(prompt)
        guard !normalized.isEmpty else { return .allowed }

        if matchesHarmfulWeaponRequest(normalized) {
            return .blocked(reason: "unsafe-weapons-instructions")
        }
        if matchesCyberAbuseRequest(normalized) {
            return .blocked(reason: "cyber-abuse-instructions")
        }
        if matchesSelfHarmMethodRequest(normalized) {
            return .blocked(reason: "self-harm-method-instructions")
        }

        return .allowed
    }

    static func isSafeRefusal(_ text: String) -> Bool {
        let normalized = normalize(text)
        let refusalSignals = [
            "i cannot help",
            "i can't help",
            "i cannot assist",
            "i can't assist",
            "i will not provide",
            "i won't provide",
            "not provide instructions",
            "could cause harm"
        ]
        let redirectionSignals = [
            "safety",
            "prevention",
            "legal",
            "safe alternative",
            "high-level",
            "emergency"
        ]
        return refusalSignals.contains(where: normalized.contains)
            && redirectionSignals.contains(where: normalized.contains)
    }

    private static func matchesHarmfulWeaponRequest(_ text: String) -> Bool {
        let action = containsAny(text, [
            "build", "make", "create", "construct", "assemble", "cook", "synthesize",
            "manufacture", "weaponize", "step by step", "instructions", "recipe"
        ])
        let target = containsAny(text, [
            "pipe bomb", "explosive", "detonator", "improvised explosive", "napalm",
            "ricin", "mustard gas", "homemade gun", "ghost gun"
        ])
        return action && target
    }

    private static func matchesCyberAbuseRequest(_ text: String) -> Bool {
        let action = containsAny(text, [
            "steal", "phish", "bypass", "exfiltrate", "keylogger", "ransomware",
            "malware", "credential", "session cookie", "hack into", "crack password"
        ])
        let target = containsAny(text, [
            "password", "account", "bank", "wallet", "private key", "token",
            "email", "icloud", "gmail", "database"
        ])
        return action && target
    }

    private static func matchesSelfHarmMethodRequest(_ text: String) -> Bool {
        let methodIntent = containsAny(text, [
            "best way to", "painless way", "how to", "method", "dose", "dosage",
            "instructions", "step by step"
        ])
        let harmTarget = containsAny(text, [
            "kill myself", "end my life", "suicide", "self harm", "overdose"
        ])
        return methodIntent && harmTarget
    }

    private static func containsAny(_ text: String, _ candidates: [String]) -> Bool {
        candidates.contains { text.contains($0) }
    }

    private static func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s\-]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

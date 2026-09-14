import Foundation

/// A suggested model switch for the current turn. The advisor never switches a
/// model itself — the composer shows this as a dismissible banner.
struct ModelSuggestion: Equatable, Identifiable {
    enum Reason: Equatable {
        case vision
        case unfitModel
        case tooling

        var message: String {
            switch self {
            case .vision:
                return "This prompt has an image, but the current model can't read images."
            case .unfitModel:
                return "The current model is marked unfit for this device."
            case .tooling:
                return "This prompt looks like it needs a tool, but the current model has no verified tool calling."
            }
        }
    }

    let model: InstalledModel
    let reason: Reason

    var id: UUID { model.catalogItem.id }
}

/// Pure, side-effect-free model advice (spec §2, feature 3). Rules are evaluated
/// in priority order and the first match wins:
///
/// 1. An image is attached and the current model has no verified vision.
/// 2. The current model's audit verdict is red.
/// 3. A document search or local-tool intent is detected and the current model
///    has no verified tool calling.
///
/// "Best" candidate = green verdict first, then recommended for the device tier,
/// then smallest disk size. Candidates must be installed and allowed on the tier.
enum ModelSuggestionAdvisor {

    static func suggestion(
        prompt: String,
        hasImage: Bool,
        hasDocuments: Bool,
        current: InstalledModel?,
        installed: [InstalledModel],
        profiles: RuntimeProfileStore,
        tier: DeviceTier
    ) -> ModelSuggestion? {
        let installedReady = installed.filter { $0.installState == .installed }
        guard !installedReady.isEmpty else { return nil }

        // Rule 1: vision.
        if hasImage {
            let currentVision = current.map { resolved($0, profiles).vision }
            if current == nil || currentVision != .imageAndText {
                if let model = best(
                    in: installedReady.filter { resolved($0, profiles).vision == .imageAndText },
                    profiles: profiles,
                    tier: tier
                ) {
                    return ModelSuggestion(model: model, reason: .vision)
                }
            }
        }

        // Rule 2: red verdict on the current model.
        if let current, verdictRank(resolved(current, profiles).verdict) == 2 {
            // Rule 2 asks specifically for the best *green* installed model.
            if let model = best(
                in: installedReady.filter { resolved($0, profiles).verdict == .green },
                profiles: profiles,
                tier: tier
            ) {
                return ModelSuggestion(model: model, reason: .unfitModel)
            }
        }

        // Rule 3: tool intent without verified tool calling.
        if hasToolIntent(prompt: prompt, hasDocuments: hasDocuments) {
            let currentTools = current.map { resolved($0, profiles).tools } ?? nil
            if currentTools == nil {
                if let model = best(
                    in: installedReady.filter { resolved($0, profiles).tools != nil },
                    profiles: profiles,
                    tier: tier
                ) {
                    return ModelSuggestion(model: model, reason: .tooling)
                }
            }
        }

        return nil
    }

    static func resolved(_ model: InstalledModel, _ profiles: RuntimeProfileStore) -> ResolvedModel {
        ModelRuntimeResolver.resolve(catalog: model.catalogItem, store: profiles)
    }

    /// Green (0) ranks before yellow (1) and red (2).
    private static func verdictRank(_ verdict: Verdict) -> Int {
        switch verdict {
        case .green: return 0
        case .yellow: return 1
        case .red: return 2
        }
    }

    /// True when the prompt reads like it needs a local tool or a document lookup.
    private static func hasToolIntent(prompt: String, hasDocuments: Bool) -> Bool {
        if hasDocuments { return true }
        if UpfrontToolDetector.canHandleLocally(prompt: prompt) { return true }

        let lowered = prompt.lowercased()
        let documentTerms = ["my document", "the document", "this document", "the pdf", "my pdf",
                             "attached file", "the file", "according to", "in the doc"]
        return documentTerms.contains { lowered.contains($0) }
    }

    /// Applies the ordering rules and returns the single best candidate.
    private static func best(
        in candidates: [InstalledModel],
        profiles: RuntimeProfileStore,
        tier: DeviceTier
    ) -> InstalledModel? {
        candidates
            .filter { tier >= $0.catalogItem.minimumTier }
            .sorted { lhs, rhs in
                let lhsResolved = resolved(lhs, profiles)
                let rhsResolved = resolved(rhs, profiles)

                let lhsVerdict = verdictRank(lhsResolved.verdict)
                let rhsVerdict = verdictRank(rhsResolved.verdict)
                if lhsVerdict != rhsVerdict { return lhsVerdict < rhsVerdict }

                let lhsRecommended = isRecommendedForTier(lhs, tier: tier)
                let rhsRecommended = isRecommendedForTier(rhs, tier: tier)
                if lhsRecommended != rhsRecommended { return lhsRecommended }

                return lhs.catalogItem.parsedDiskSizeGBForEstimator < rhs.catalogItem.parsedDiskSizeGBForEstimator
            }
            .first
    }

    private static func isRecommendedForTier(_ model: InstalledModel, tier: DeviceTier) -> Bool {
        if model.catalogItem.testedDeviceTier == tier { return true }
        return model.catalogItem.runtimeStatus == .recommended || model.catalogItem.recommendedForIPhone
    }
}

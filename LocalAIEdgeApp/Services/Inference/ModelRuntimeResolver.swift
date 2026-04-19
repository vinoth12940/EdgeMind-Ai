// LocalAIEdgeApp/Services/Inference/ModelRuntimeResolver.swift
import Foundation

struct ResolvedModel {
    let catalog: ModelCatalogItem
    let thinking: ThinkFormat?         // runtime will parse think blocks for this model
    let tools: ToolCallFormat?         // runtime will run the agentic tool-call loop
    let vision: VisionMode             // runtime accepts image attachments
    let leakTokens: [String]
    let maxTokens: Int
    let verdict: Verdict
    let isMismatch: Bool               // true when catalog claims a capability the profile denies
}

enum ModelRuntimeResolver {
    static func resolve(catalog: ModelCatalogItem, store: RuntimeProfileStore) -> ResolvedModel {
        let profile = store.profile(for: catalog.id) ?? RuntimeProfile.safeMinimum(catalogID: catalog.id)

        // Detect mismatches so UI can surface "claimed but not verified".
        let visionMismatch = catalog.supportsVision && profile.verifiedVision == .none
        let toolMismatch = catalog.supportsToolCalling && profile.verifiedToolCalling == nil
        let thinkMismatch = catalog.isThinkingModel && profile.verifiedThinking == nil

        return ResolvedModel(
            catalog: catalog,
            thinking: profile.verifiedThinking,
            tools: profile.verifiedToolCalling,
            vision: profile.verifiedVision,
            leakTokens: profile.knownLeakTokens,
            maxTokens: profile.recommendedMaxTokens,
            verdict: profile.auditVerdict,
            isMismatch: visionMismatch || toolMismatch || thinkMismatch
        )
    }
}

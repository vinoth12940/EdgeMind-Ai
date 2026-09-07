import Foundation

/// Per-generation performance metrics surfaced to the UI ("12.4 tok/s · 0.8s to
/// first token") and persisted on `ChatMessage`.
///
/// Two sources feed the fields:
/// - **Exact counts** (`outputTokens`) where the runtime reports them natively —
///   llama.cpp tracks `generatedTokenCount`; MLX's `GenerateCompletionInfo`
///   reports token counts and tokens/sec.
/// - **Delta-count fallback** (`deltaCount`) — the number of `.textDelta` /
///   `.thinkingDelta` events observed by `StreamProcessor`. Coarser than real
///   token counts (a single delta can carry several tokens), but always
///   available across every backend since all streams funnel through
///   `StreamProcessor`.
///
/// `tokensPerSecond` prefers an exact count when present and falls back to the
/// delta count, so the displayed value is never nonsensical.
struct GenerationStats: Codable, Hashable, Sendable {
    /// Wall-clock seconds from stream start to the first emitted
    /// `.textDelta` / `.thinkingDelta`. `nil` if no content was produced.
    var timeToFirstToken: TimeInterval?
    /// Wall-clock seconds from stream start to `.done`.
    var totalDuration: TimeInterval
    /// Exact output-token count reported by the runtime, when available.
    var outputTokens: Int?
    /// Number of stream deltas observed (fallback approximation for tok/s).
    var deltaCount: Int

    init(
        timeToFirstToken: TimeInterval? = nil,
        totalDuration: TimeInterval,
        outputTokens: Int? = nil,
        deltaCount: Int = 0
    ) {
        self.timeToFirstToken = timeToFirstToken
        self.totalDuration = totalDuration
        self.outputTokens = outputTokens
        self.deltaCount = deltaCount
    }

    /// Tokens used for the rate calculation — exact count preferred, delta
    /// count as fallback.
    var effectiveTokenCount: Int {
        outputTokens ?? deltaCount
    }

    /// Tokens/second over the total generation duration. `nil` when duration is
    /// too short or no tokens were produced to avoid div-by-zero / noise.
    var tokensPerSecond: Double? {
        guard totalDuration > 0.05, effectiveTokenCount > 0 else { return nil }
        return Double(effectiveTokenCount) / totalDuration
    }

    /// True when the rate is derived from exact runtime counts rather than the
    /// delta-count approximation. Drives a "(approx)" qualifier in the footer.
    var isApproximate: Bool {
        outputTokens == nil
    }
}

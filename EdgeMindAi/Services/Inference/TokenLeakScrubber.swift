import Foundation

/// Mid-stream scrubber that removes known leak tokens before emitting text to the UI.
/// Holds a lookahead buffer so a leak token split across two incoming chunks is still caught.
actor TokenLeakScrubber {
    private let leakTokens: [String]
    private let lookahead: Int
    private var buffer = ""

    init(leakTokens: [String]) {
        let longest = leakTokens.map(\.count).max() ?? 0
        self.lookahead = max(24, longest + 8)
        self.leakTokens = leakTokens
    }

    func feed(_ chunk: String) -> String {
        buffer += chunk
        stripKnownLeaks(in: &buffer)
        let heldCount = heldSuffixLength(in: buffer)

        if heldCount == 0 {
            defer { buffer = "" }
            return buffer
        }

        let splitIndex = buffer.index(buffer.endIndex, offsetBy: -heldCount)
        let emitted = String(buffer[..<splitIndex])
        buffer = String(buffer[splitIndex...])
        return emitted
    }

    func flush() -> String {
        defer { buffer = "" }
        var output = buffer
        stripKnownLeaks(in: &output)
        return output
    }

    private func stripKnownLeaks(in text: inout String) {
        guard !text.isEmpty, !leakTokens.isEmpty else { return }
        for token in leakTokens {
            text = text.replacingOccurrences(of: token, with: "")
        }
    }

    private func heldSuffixLength(in text: String) -> Int {
        guard !text.isEmpty, !leakTokens.isEmpty else { return 0 }

        let candidateLimit = min(lookahead, text.count)
        var best = 0

        for length in 1...candidateLimit {
            let suffix = String(text.suffix(length))
            if leakTokens.contains(where: { $0.hasPrefix(suffix) }) {
                best = length
            }
        }

        return best
    }
}

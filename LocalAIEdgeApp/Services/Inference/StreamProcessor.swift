import Foundation

enum StreamEvent: Sendable {
    case textDelta(String)
    case thinkingDelta(String)
    case thinkingDone(durationSeconds: Int)
    case toolCall(name: String, argsJSON: String)
    case done
}

actor StreamProcessor {
    private let rawStream: AsyncStream<String>
    private let leakTokens: [String]
    private let v2Enabled: Bool
    private let hangTimeout: TimeInterval
    private let repetitionNgram: Int
    private let repetitionCount: Int
    private let activeThinkFormats: Set<ThinkFormat>

    // Tag pairings: opening tag (lowercased) -> closing tag (lowercased)
    fileprivate static let thinkTagPairs: [String: String] = [
        "<think>": "</think>",
        "<thinking>": "</thinking>",
        "<reasoning>": "</reasoning>"
    ]
    fileprivate static let qwenNativeOpenTags = ["<|im_start|>think", "<|think|>"]
    fileprivate static let qwenNativeCloseTags = ["<|im_end|>", "<|/think|>"]
    fileprivate static let gemmaChannelOpenTag = "<|channel>thought\n"
    fileprivate static let gemmaChannelCloseTags = ["<|channel>", "<channel|>"]

    init(
        rawStream: AsyncStream<String>,
        leakTokens: [String] = [],
        v2Enabled: Bool = false,
        hangTimeout: TimeInterval = 15,
        repetitionNgram: Int = 6,
        repetitionCount: Int = 3,
        activeThinkFormats: Set<ThinkFormat> = []
    ) {
        self.rawStream = rawStream
        self.v2Enabled = v2Enabled
        self.hangTimeout = hangTimeout
        self.repetitionNgram = repetitionNgram
        self.repetitionCount = repetitionCount
        self.activeThinkFormats = activeThinkFormats
        self.leakTokens = Self.filteredLeakTokens(leakTokens, activeThinkFormats: activeThinkFormats)
    }

    func process() -> AsyncStream<StreamEvent> {
        v2Enabled ? processV2() : processV1()
    }

    private func processV1() -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            Task {
                var parser = ParserState(activeThinkFormats: activeThinkFormats)
                for await token in rawStream {
                    let outcome = parser.consume(token) { event in
                        continuation.yield(event)
                        return true
                    }
                    if outcome == .terminateStream {
                        continuation.finish()
                        return
                    }
                }

                parser.finish { event in
                    continuation.yield(event)
                    return true
                }
                continuation.yield(.done)
                continuation.finish()
            }
        }
    }

    private func processV2() -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            let scrubber = TokenLeakScrubber(leakTokens: leakTokens)
            let repetitionGuard = RepetitionGuard(ngram: repetitionNgram, threshold: repetitionCount)
            let finishState = StreamFinishState()
            let taskBox = TaskBox()

            func emit(_ event: StreamEvent) {
                guard !finishState.isFinished else { return }
                if case .done = event {
                    continuation.yield(event)
                    return
                }
                finishState.markEmitted()
                continuation.yield(event)
            }

            func finish(includeDone: Bool, fallbackMessage: String? = nil) {
                taskBox.watchdog?.cancel()
                guard finishState.finishIfNeeded() else { return }
                if let fallbackMessage, !finishState.hasEmitted {
                    continuation.yield(.textDelta(fallbackMessage))
                } else if includeDone, !finishState.hasEmitted {
                    continuation.yield(.textDelta("_The model did not produce output. Try a different model or prompt._"))
                }
                if includeDone {
                    continuation.yield(.done)
                }
                continuation.finish()
                taskBox.producer?.cancel()
            }

            func armWatchdog() {
                taskBox.watchdog?.cancel()
                taskBox.watchdog = Task {
                    do {
                        try await Task.sleep(for: .seconds(hangTimeout))
                    } catch {
                        return
                    }
                    finish(
                        includeDone: true,
                        fallbackMessage: "_The model did not produce output before the timeout. Try a smaller model or shorter prompt._"
                    )
                }
            }

            taskBox.producer = Task {
                var parser = ParserState(activeThinkFormats: activeThinkFormats)
                var fenceCount = 0

                func handleEvent(_ event: StreamEvent) -> Bool {
                    guard !finishState.isFinished else { return false }

                    switch event {
                    case .textDelta(let text):
                        let insideFence = (fenceCount % 2) == 1
                        if !insideFence, repetitionGuard.shouldAbort(appending: text) {
                            finish(includeDone: true)
                            return false
                        }
                        emit(event)
                        fenceCount += text.components(separatedBy: "```").count - 1
                        return !finishState.isFinished
                    default:
                        emit(event)
                        return !finishState.isFinished
                    }
                }

                armWatchdog()

                for await rawChunk in rawStream {
                    if Task.isCancelled || finishState.isFinished {
                        return
                    }

                    armWatchdog()
                    let cleaned = await scrubber.feed(rawChunk)
                    guard !cleaned.isEmpty else { continue }

                    let outcome = parser.consume(cleaned, emit: handleEvent)
                    if outcome == .terminateStream {
                        finish(includeDone: false)
                        return
                    }
                }

                taskBox.watchdog?.cancel()
                guard !finishState.isFinished else { return }

                let residue = await scrubber.flush()
                if !residue.isEmpty {
                    let outcome = parser.consume(residue, emit: handleEvent)
                    if outcome == .terminateStream {
                        finish(includeDone: false)
                        return
                    }
                }

                parser.finish(emit: handleEvent)
                finish(includeDone: true)
            }

            continuation.onTermination = { _ in
                taskBox.watchdog?.cancel()
                taskBox.producer?.cancel()
            }
        }
    }

    private static func filteredLeakTokens(_ leakTokens: [String], activeThinkFormats: Set<ThinkFormat>) -> [String] {
        leakTokens.filter { token in
            let normalized = token.lowercased()
            if activeThinkFormats.contains(.qwenNative),
               normalized == "<|im_start|>" || normalized == "<|im_end|>" {
                return false
            }
            if activeThinkFormats.contains(.gemmaChannel),
               normalized == "<|channel>" || normalized == "<channel|>" {
                return false
            }
            return true
        }
    }

    fileprivate static func earliestMatch(in text: String, candidates: [String]) -> TokenMatch? {
        var bestMatch: TokenMatch?

        for candidate in candidates {
            guard let range = text.range(of: candidate, options: .caseInsensitive) else { continue }
            let match = TokenMatch(token: candidate, range: range)

            if let currentBest = bestMatch {
                if range.lowerBound < currentBest.range.lowerBound
                    || (range.lowerBound == currentBest.range.lowerBound && candidate.count > currentBest.token.count) {
                    bestMatch = match
                }
            } else {
                bestMatch = match
            }
        }

        return bestMatch
    }
}

private enum ParseOutcome {
    case continueProcessing
    case terminateStream
}

private struct TokenMatch {
    let token: String
    let range: Range<String.Index>
}

private enum ThinkMode {
    case xml(openTag: String, closeTag: String)
    case qwenNative
    case gemmaChannel

    var closeTokens: [String] {
        switch self {
        case .xml(_, let closeTag):
            return [closeTag]
        case .qwenNative:
            return StreamProcessor.qwenNativeCloseTags
        case .gemmaChannel:
            return StreamProcessor.gemmaChannelCloseTags
        }
    }
}

private struct ParserState {
    private var lineBuffer = ""
    private var thinkBuffer = ""
    private var thinkMode: ThinkMode?
    private var thinkStart: Date?
    private var toolCallBuffer: String?
    private var toolCallFired = false
    private let activeThinkFormats: Set<ThinkFormat>

    init(activeThinkFormats: Set<ThinkFormat>) {
        self.activeThinkFormats = activeThinkFormats
    }

    mutating func consume(_ chunk: String, emit: (StreamEvent) -> Bool) -> ParseOutcome {
        var remaining = chunk

        while !remaining.isEmpty {
            if toolCallBuffer != nil {
                if let closeMatch = StreamProcessor.earliestMatch(in: remaining, candidates: ["</tool_call>", "<tool_call|>"]) {
                    toolCallBuffer! += String(remaining[..<closeMatch.range.lowerBound])
                    remaining = String(remaining[closeMatch.range.upperBound...])
                    let raw = toolCallBuffer!
                    toolCallBuffer = nil

                    if !toolCallFired {
                        toolCallFired = true
                        if let data = raw.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let name = json["name"] as? String,
                           !name.isEmpty {
                            guard emit(.toolCall(name: name, argsJSON: raw)) else {
                                return .terminateStream
                            }
                            return .terminateStream
                        }
                    }

                    guard emit(.textDelta(raw)) else {
                        return .terminateStream
                    }
                } else {
                    toolCallBuffer! += remaining
                    remaining = ""
                }
                continue
            }

            if let mode = thinkMode {
                let closeMatch = StreamProcessor.earliestMatch(in: remaining, candidates: mode.closeTokens)
                if !toolCallFired,
                   let toolMatch = StreamProcessor.earliestMatch(in: remaining, candidates: ["<tool_call>", "<|tool_call>"]),
                   closeMatch == nil || toolMatch.range.lowerBound < closeMatch!.range.lowerBound {
                    let beforeTool = String(remaining[..<toolMatch.range.lowerBound])
                    if !beforeTool.isEmpty, !emit(.thinkingDelta(beforeTool)) {
                        return .terminateStream
                    }
                    let duration = thinkStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
                    if !emit(.thinkingDone(durationSeconds: max(1, duration))) {
                        return .terminateStream
                    }
                    thinkBuffer = ""
                    thinkMode = nil
                    thinkStart = nil
                    remaining = String(remaining[toolMatch.range.upperBound...])
                    toolCallBuffer = ""
                    continue
                }

                if let closeMatch {
                    thinkBuffer += String(remaining[..<closeMatch.range.lowerBound])
                    remaining = String(remaining[closeMatch.range.upperBound...])
                    if !thinkBuffer.isEmpty, !emit(.thinkingDelta(thinkBuffer)) {
                        return .terminateStream
                    }
                    let duration = thinkStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
                    if !emit(.thinkingDone(durationSeconds: max(1, duration))) {
                        return .terminateStream
                    }
                    thinkBuffer = ""
                    thinkMode = nil
                    thinkStart = nil
                } else {
                    if !emit(.thinkingDelta(remaining)) {
                        return .terminateStream
                    }
                    thinkBuffer = ""
                    remaining = ""
                }
                continue
            }

            if let thinkOpen = nextThinkOpen(in: remaining) {
                lineBuffer += String(remaining[..<thinkOpen.match.range.lowerBound])
                let textOutcome = flushLineBuffer(emit: emit)
                if textOutcome == .terminateStream {
                    return .terminateStream
                }
                remaining = String(remaining[thinkOpen.match.range.upperBound...])
                thinkMode = thinkOpen.mode
                thinkStart = Date()
                continue
            }

            if !toolCallFired,
               let toolOpen = StreamProcessor.earliestMatch(in: remaining, candidates: ["<tool_call>", "<|tool_call>"]) {
                lineBuffer += String(remaining[..<toolOpen.range.lowerBound])
                let textOutcome = flushLineBuffer(emit: emit)
                if textOutcome == .terminateStream {
                    return .terminateStream
                }
                remaining = String(remaining[toolOpen.range.upperBound...])
                toolCallBuffer = ""
                continue
            }

            lineBuffer += remaining
            remaining = ""
            let textOutcome = flushLineBuffer(emit: emit)
            if textOutcome == .terminateStream {
                return .terminateStream
            }
        }

        return .continueProcessing
    }

    mutating func finish(emit: (StreamEvent) -> Bool) {
        if thinkMode != nil {
            if !thinkBuffer.isEmpty {
                _ = emit(.thinkingDelta(thinkBuffer))
            }
            let duration = thinkStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
            _ = emit(.thinkingDone(durationSeconds: max(1, duration)))
            thinkBuffer = ""
            thinkMode = nil
            thinkStart = nil
        } else if let toolCallBuffer {
            _ = emit(.textDelta(toolCallBuffer))
            self.toolCallBuffer = nil
        }

        if !lineBuffer.isEmpty {
            _ = emit(.textDelta(lineBuffer))
            lineBuffer = ""
        }
    }

    private mutating func flushLineBuffer(emit: (StreamEvent) -> Bool) -> ParseOutcome {
        var lines = lineBuffer.components(separatedBy: "\n")
        lineBuffer = lines.removeLast()
        for line in lines {
            if !emit(.textDelta(line + "\n")) {
                return .terminateStream
            }
        }
        return .continueProcessing
    }

    private func nextThinkOpen(in text: String) -> (match: TokenMatch, mode: ThinkMode)? {
        var matches: [(TokenMatch, ThinkMode)] = []

        for (openTag, closeTag) in StreamProcessor.thinkTagPairs {
            if let match = StreamProcessor.earliestMatch(in: text, candidates: [openTag]) {
                matches.append((match, .xml(openTag: openTag, closeTag: closeTag)))
            }
        }

        if activeThinkFormats.contains(.qwenNative),
           let match = StreamProcessor.earliestMatch(in: text, candidates: StreamProcessor.qwenNativeOpenTags) {
            matches.append((match, .qwenNative))
        }

        if activeThinkFormats.contains(.gemmaChannel),
           let match = StreamProcessor.earliestMatch(in: text, candidates: [StreamProcessor.gemmaChannelOpenTag]) {
            matches.append((match, .gemmaChannel))
        }

        return matches.min { lhs, rhs in
            if lhs.0.range.lowerBound == rhs.0.range.lowerBound {
                return lhs.0.token.count > rhs.0.token.count
            }
            return lhs.0.range.lowerBound < rhs.0.range.lowerBound
        }
    }
}

private final class RepetitionGuard {
    private let ngram: Int
    private let threshold: Int
    private var tokenWindow: [String] = []

    init(ngram: Int, threshold: Int) {
        self.ngram = ngram
        self.threshold = threshold
    }

    func shouldAbort(appending text: String) -> Bool {
        let newTokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !newTokens.isEmpty else { return false }

        tokenWindow.append(contentsOf: newTokens)
        trimIfNeeded()

        guard tokenWindow.count >= ngram else { return false }
        let referenceStart = tokenWindow.count - ngram
        let reference = Array(tokenWindow[referenceStart...])

        let maxPeriod = min(ngram, max(1, referenceStart))
        for period in 1...maxPeriod {
            var matchedRepeats = 0
            var candidateStart = referenceStart - period

            while candidateStart >= 0, matchedRepeats < threshold {
                let candidateEnd = candidateStart + ngram
                if candidateEnd > tokenWindow.count {
                    break
                }
                if Array(tokenWindow[candidateStart..<candidateEnd]) != reference {
                    break
                }
                matchedRepeats += 1
                candidateStart -= period
            }

            if matchedRepeats >= threshold {
                return true
            }
        }
        return false
    }

    private func trimIfNeeded() {
        if tokenWindow.count > 256 {
            tokenWindow.removeFirst(tokenWindow.count - 256)
        }
    }
}

private final class StreamFinishState: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var emittedAny = false

    var isFinished: Bool {
        lock.withLock { finished }
    }

    var hasEmitted: Bool {
        lock.withLock { emittedAny }
    }

    func markEmitted() {
        lock.withLock {
            emittedAny = true
        }
    }

    func finishIfNeeded() -> Bool {
        lock.withLock {
            if finished { return false }
            finished = true
            return true
        }
    }
}

private final class TaskBox: @unchecked Sendable {
    var producer: Task<Void, Never>?
    var watchdog: Task<Void, Never>?
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

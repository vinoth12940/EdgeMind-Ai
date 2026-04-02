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

    // Tag pairings: opening tag (lowercased) → closing tag (lowercased)
    private static let thinkTagPairs: [String: String] = [
        "<think>": "</think>",
        "<thinking>": "</thinking>",
        "<reasoning>": "</reasoning>"
    ]

    init(rawStream: AsyncStream<String>) {
        self.rawStream = rawStream
    }

    func process() -> AsyncStream<StreamEvent> {
        AsyncStream { continuation in
            Task {
                var lineBuffer = ""          // accumulates until \n or block boundary
                var thinkBuffer = ""         // content inside think block
                var thinkOpenTag: String?    // which open tag is active (lowercased)
                var thinkStart: Date?
                var toolCallBuffer: String?  // non-nil while inside <tool_call>
                var toolCallFired = false    // guard: only one per stream

                func flush(_ text: String) {
                    if !text.isEmpty { continuation.yield(.textDelta(text)) }
                }

                func processBuffer(_ buf: inout String) {
                    // Split on newlines; keep last incomplete line in buffer
                    var lines = buf.components(separatedBy: "\n")
                    buf = lines.removeLast() // last element may be incomplete
                    for line in lines {
                        flush(line + "\n")
                    }
                }

                for await token in rawStream {
                    var remaining = token

                    while !remaining.isEmpty {
                        // ── Tool call buffering ──────────────────────────────
                        if toolCallBuffer != nil {
                            if let closeRange = remaining.range(of: "</tool_call>", options: .caseInsensitive) {
                                toolCallBuffer! += String(remaining[..<closeRange.lowerBound])
                                remaining = String(remaining[closeRange.upperBound...])
                                let raw = toolCallBuffer!
                                toolCallBuffer = nil
                                // Parse JSON — mark fired regardless so only one tool call per stream
                                if !toolCallFired {
                                    toolCallFired = true
                                    if let data = raw.data(using: .utf8),
                                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                                       let name = json["name"], !name.isEmpty {
                                        continuation.yield(.toolCall(name: name, argsJSON: raw))
                                        // Don't emit .done — ChatView will re-invoke inference
                                        // Remaining tokens after </tool_call> are discarded for this stream
                                        continuation.finish()
                                        return
                                    } else {
                                        // Parse failed — flush as text
                                        flush(raw)
                                    }
                                } else {
                                    // Already fired — flush as text
                                    flush(raw)
                                }
                            } else {
                                toolCallBuffer! += remaining
                                remaining = ""
                            }
                            continue
                        }

                        // ── Think block routing ──────────────────────────────
                        if let openTag = thinkOpenTag {
                            let closeTag = Self.thinkTagPairs[openTag]!
                            if let closeRange = remaining.range(of: closeTag, options: .caseInsensitive) {
                                thinkBuffer += String(remaining[..<closeRange.lowerBound])
                                remaining = String(remaining[closeRange.upperBound...])
                                // Yield any buffered thinking content before signalling done
                                if !thinkBuffer.isEmpty {
                                    continuation.yield(.thinkingDelta(thinkBuffer))
                                }
                                let duration = thinkStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
                                continuation.yield(.thinkingDone(durationSeconds: max(1, duration)))
                                thinkBuffer = ""
                                thinkOpenTag = nil
                                thinkStart = nil
                            } else {
                                continuation.yield(.thinkingDelta(remaining))
                                // thinkBuffer only used for auto-close flush; clear after yielding
                                thinkBuffer = ""
                                remaining = ""
                            }
                            continue
                        }

                        // ── Detect opening think tag ─────────────────────────
                        // Sort by length descending so <thinking>/<reasoning> match before <think>
                        var foundThink = false
                        for openTag in Self.thinkTagPairs.keys.sorted(by: { $0.count > $1.count }) {
                            if let openRange = remaining.range(of: openTag, options: .caseInsensitive) {
                                // Flush text before the tag
                                let before = String(remaining[..<openRange.lowerBound])
                                lineBuffer += before
                                processBuffer(&lineBuffer)
                                remaining = String(remaining[openRange.upperBound...])
                                thinkOpenTag = openTag
                                thinkStart = Date()
                                foundThink = true
                                break
                            }
                        }
                        if foundThink { continue }

                        // ── Detect opening tool_call tag ─────────────────────
                        if !toolCallFired,
                           let openRange = remaining.range(of: "<tool_call>", options: .caseInsensitive) {
                            let before = String(remaining[..<openRange.lowerBound])
                            lineBuffer += before
                            processBuffer(&lineBuffer)
                            remaining = String(remaining[openRange.upperBound...])
                            toolCallBuffer = ""
                            continue
                        }

                        // ── Normal text ──────────────────────────────────────
                        lineBuffer += remaining
                        remaining = ""
                        processBuffer(&lineBuffer)
                    }
                }

                // Stream ended — flush residuals
                if let openTag = thinkOpenTag {
                    // Auto-close unclosed think block
                    let duration = thinkStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
                    if !thinkBuffer.isEmpty {
                        continuation.yield(.thinkingDelta(thinkBuffer))
                    }
                    continuation.yield(.thinkingDone(durationSeconds: max(1, duration)))
                    _ = openTag
                } else if let tb = toolCallBuffer {
                    // Stream ended before </tool_call> — flush as text
                    flush(tb)
                }

                // Flush remaining line buffer
                if !lineBuffer.isEmpty { flush(lineBuffer) }

                continuation.yield(.done)
                continuation.finish()
            }
        }
    }
}

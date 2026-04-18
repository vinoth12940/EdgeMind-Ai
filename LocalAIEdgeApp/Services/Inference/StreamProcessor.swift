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

                // NOTE: Tags split across token boundaries (e.g. one token ends with "<thi"
                // and the next starts with "nk>") are not detected. Models that stream
                // at word/subword granularity rarely split XML tags, so this is accepted.
                for await token in rawStream {
                    var remaining = token

                    while !remaining.isEmpty {
                        // ── Tool call buffering ──────────────────────────────
                        if toolCallBuffer != nil {
                            // Detect both standard </tool_call> and Gemma 4 native <tool_call|>
                            let closeRange = remaining.range(of: "</tool_call>", options: .caseInsensitive)
                                ?? remaining.range(of: "<tool_call|>", options: .caseInsensitive)
                            if let closeRange {
                                toolCallBuffer! += String(remaining[..<closeRange.lowerBound])
                                remaining = String(remaining[closeRange.upperBound...])
                                let raw = toolCallBuffer!
                                toolCallBuffer = nil
                                // Parse JSON — mark fired regardless so only one tool call per stream
                                if !toolCallFired {
                                    // Guard fires on first <tool_call> block regardless of JSON validity.
                                    // This prevents infinite loops: if the model re-emits a tool call in the
                                    // follow-up stream, it's treated as plain text even if the first was bad JSON.
                                    toolCallFired = true
                                    if let data = raw.data(using: .utf8),
                                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                       let name = json["name"] as? String, !name.isEmpty {
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

                            // ── Check for <tool_call> inside think block ─────
                            // Some models (Qwen 3) emit tool calls inside thinking.
                            // If we detect <tool_call> before the closing think tag,
                            // close thinking early and switch to tool call buffering.
                            if !toolCallFired {
                                let toolOpenRange = remaining.range(of: "<tool_call>", options: .caseInsensitive)
                                    ?? remaining.range(of: "<|tool_call>", options: .caseInsensitive)
                                let thinkCloseRange = remaining.range(of: closeTag, options: .caseInsensitive)

                                if let toolRange = toolOpenRange,
                                   (thinkCloseRange == nil || toolRange.lowerBound < thinkCloseRange!.lowerBound) {
                                    // Tool call found before think close — end thinking, start tool buffering
                                    let beforeTool = String(remaining[..<toolRange.lowerBound])
                                    if !beforeTool.isEmpty {
                                        continuation.yield(.thinkingDelta(beforeTool))
                                    }
                                    let duration = thinkStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
                                    continuation.yield(.thinkingDone(durationSeconds: max(1, duration)))
                                    thinkBuffer = ""
                                    thinkOpenTag = nil
                                    thinkStart = nil
                                    remaining = String(remaining[toolRange.upperBound...])
                                    toolCallBuffer = ""
                                    continue
                                }
                            }

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
                        // Detect both standard <tool_call> and Gemma 4 native <|tool_call>
                        if !toolCallFired,
                           let openRange = remaining.range(of: "<tool_call>", options: .caseInsensitive)
                                ?? remaining.range(of: "<|tool_call>", options: .caseInsensitive) {
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
                if thinkOpenTag != nil {
                    // Auto-close unclosed think block
                    let duration = thinkStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
                    if !thinkBuffer.isEmpty {
                        continuation.yield(.thinkingDelta(thinkBuffer))
                    }
                    continuation.yield(.thinkingDone(durationSeconds: max(1, duration)))
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

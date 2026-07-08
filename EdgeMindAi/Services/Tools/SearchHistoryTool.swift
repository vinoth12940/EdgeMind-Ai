// LocalAIEdgeApp/Services/Tools/SearchHistoryTool.swift
import Foundation

/// `search_chats` — search the user's OWN past chat sessions for a keyword/phrase.
/// 100% local: reads only `ToolContext.chatSessions`, never leaves the device.
/// Returns matching excerpts with their session title so the model can reference them.
///
/// This is a flagship privacy-safe agentic capability: the model can recall what the
/// user previously discussed without any cloud sync or upload.
struct SearchHistoryTool: Tool {
    let name = "search_chats"

    let definition = ToolDefinition(
        name: "search_chats",
        summary: "Search the user's past conversations on THIS device for a keyword or phrase. Returns matching excerpts with the session title. All data stays local.",
        parameters: ["query": "the keyword or phrase to look for in past chats"]
    )

    /// Maximum number of matches returned, to keep the injected prompt small.
    static let maxMatches = 5
    /// Maximum characters of an excerpt shown per match.
    static let excerptLength = 220

    func run(argsJSON: String, context: ToolContext) async -> ToolResult {
        guard let query = SearchHistoryTool.extractQuery(argsJSON), !query.isEmpty else {
            return .error(toolName: name,
                          message: "Missing \"query\" argument. Send {\"query\": \"keyword\"}.")
        }
        let needle = query.lowercased()
        let sessions = context.chatSessions

        if sessions.isEmpty {
            return ToolResult(toolName: name, output: "No past conversations found on this device.")
        }

        var matches: [Match] = []
        for session in sessions {
            let titleHit = session.title.lowercased().contains(needle)
            for message in session.messages where message.role == .user || message.role == .assistant {
                let body = message.text
                guard let range = body.lowercased().range(of: needle) else { continue }
                let excerpt = Self.excerpt(of: body, around: range)
                let m = Match(sessionTitle: session.title.isEmpty ? "Untitled" : session.title,
                              role: message.role.rawValue.capitalized,
                              excerpt: excerpt,
                              titleHit: titleHit)
                matches.append(m)
                if matches.count >= Self.maxMatches { break }
            }
            if matches.count >= Self.maxMatches { break }
        }

        if matches.isEmpty {
            return ToolResult(toolName: name,
                              output: "No matches for \"\(query)\" in \(sessions.count) past conversation\(sessions.count == 1 ? "" : "s").")
        }

        let lines = ["Found \(matches.count) match\(matches.count == 1 ? "" : "es") for \"\(query)\":"]
            + matches.enumerated().map { idx, m in
                """
                [\(idx + 1)] \(m.sessionTitle) — \(m.role):
                \(m.excerpt)
                """
            }
        return ToolResult(toolName: name, output: lines.joined(separator: "\n"))
    }

    struct Match {
        let sessionTitle: String
        let role: String
        let excerpt: String
        let titleHit: Bool
    }

    /// Builds a windowed excerpt centered on the match.
    static func excerpt(of body: String, around range: Range<String.Index>) -> String {
        let center = body.distance(from: body.startIndex, to: range.lowerBound)
        let half = Self.excerptLength / 2
        let startOffset = max(0, center - half)
        let start = body.index(body.startIndex, offsetBy: startOffset, limitedBy: body.endIndex) ?? body.startIndex
        let end = body.index(start, offsetBy: Self.excerptLength, limitedBy: body.endIndex) ?? body.endIndex
        var snippet = String(body[start..<end])
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if start != body.startIndex { snippet = "…" + snippet }
        if end != body.endIndex { snippet += "…" }
        return snippet
    }

    static func extractQuery(_ argsJSON: String) -> String? {
        let trimmed = argsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Valid JSON object: only accept a recognized query key. Do NOT fall
            // through to the bare-string path — `{}` is not a query.
            if let s = json["query"] as? String, !s.isEmpty { return s }
            if let s = json["q"] as? String, !s.isEmpty { return s }
            if let s = json["keyword"] as? String, !s.isEmpty { return s }
            return nil
        }
        // Bare string fallback (model sent the raw query, not JSON).
        if !trimmed.isEmpty { return trimmed }
        return nil
    }
}

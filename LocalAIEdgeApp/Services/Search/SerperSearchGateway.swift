import Foundation

struct SerperSearchGateway: SearchGateway {
    let apiKey: String

    func search(query: String) async throws -> SearchContext {
        guard !apiKey.isEmpty else {
            throw SearchGatewayError.invalidAPIKey(provider: "Serper")
        }

        var request = URLRequest(url: URL(string: "https://google.serper.dev/search")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-KEY")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "q": query,
            "num": 5
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SearchGatewayError.httpError(statusCode: code, provider: "Serper")
        }

        let result = try JSONDecoder().decode(SerperResponse.self, from: data)
        let organic = result.organic ?? []

        let answerText = await primaryAnswerText(from: result, organic: organic, query: query)

        var snippets: [String] = []
        if let sportsSummary = result.sportsResults?.summaryText {
            snippets.append("Sports: \(sportsSummary)")
        }
        if let knowledgeSummary = result.knowledgeGraph?.summaryText {
            snippets.append(knowledgeSummary)
        }
        snippets.append(contentsOf: organic.prefix(5).compactMap { item in
            guard let snippet = item.snippet else { return nil }
            return "\(item.title): \(snippet)"
        })

        return SearchContext(
            query: query,
            answer: answerText,
            snippets: snippets,
            citations: organic.prefix(5).map { item in
                SearchCitation(
                    title: item.title,
                    url: URL(string: item.link) ?? URL(string: "https://google.com")!,
                    snippet: String((item.snippet ?? "").prefix(200))
                )
            }
        )
    }

    private func primaryAnswerText(from result: SerperResponse, organic: [SerperOrganicResult], query: String) async -> String? {
        let directCandidates = [
            result.answerBox?.answer,
            result.answerBox?.snippet,
            result.answerBox?.snippetHighlighted?.first,
            result.sportsResults?.summaryText,
            result.knowledgeGraph?.summaryText
        ]
            .compactMap {
                $0?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        if let direct = directCandidates.first {
            return direct
        }

        guard SearchResultFallbackComposer.queryLooksLive(query), !organic.isEmpty else {
            return nil
        }

        if let livePageSummary = await fetchLivePageSummary(from: organic) {
            return livePageSummary
        }

        let sourceList = organic.prefix(3).map(\.title).joined(separator: ", ")
        return "The search results point to live pages such as \(sourceList), but they do not expose the exact live value in the returned snippet."
    }

    private func fetchLivePageSummary(from organic: [SerperOrganicResult]) async -> String? {
        let rankedSources = organic
            .prefix(4)
            .sorted { lhs, rhs in
                liveSourcePriority(for: lhs.link) < liveSourcePriority(for: rhs.link)
            }

        for item in rankedSources {
            guard let url = URL(string: item.link) else { continue }

            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    continue
                }

                let html = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                guard !html.isEmpty else { continue }

                if let summary = LivePageSummaryExtractor.extractSummary(from: html, fallbackTitle: item.title) {
                    return summary
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func liveSourcePriority(for rawURL: String) -> Int {
        guard let host = URL(string: rawURL)?.host?.lowercased() else { return 99 }

        if host.contains("cricbuzz") { return 0 }
        if host.contains("espncricinfo") { return 1 }
        if host.contains("iplt20") { return 2 }
        if host.contains("livescore") { return 3 }
        return 10
    }
}

// MARK: - Serper API Models

private struct SerperResponse: Decodable {
    let answerBox: SerperAnswerBox?
    let knowledgeGraph: SerperKnowledgeGraph?
    let sportsResults: SerperSportsResults?
    let organic: [SerperOrganicResult]?
}

private struct SerperAnswerBox: Decodable {
    let answer: String?
    let snippet: String?
    let snippetHighlighted: [String]?
}

private struct SerperKnowledgeGraph: Decodable {
    let title: String?
    let type: String?
    let description: String?

    var summaryText: String? {
        let parts = [title, type, description]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " — ")
    }
}

private struct SerperSportsResults: Decodable {
    let title: String?
    let gameSpotlight: String?
    let snippet: String?

    var summaryText: String? {
        let parts = [title, gameSpotlight, snippet]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " — ")
    }
}

private struct SerperOrganicResult: Decodable {
    let title: String
    let link: String
    let snippet: String?
}

enum LivePageSummaryExtractor {
    static func extractSummary(from html: String, fallbackTitle: String) -> String? {
        let cleanedHTML = html.replacingOccurrences(of: "<!-- -->", with: "")

        let candidatePatterns = [
            #"title="([^"]+)""#,
            #"<title>([^<]+)</title>"#
        ]

        var candidates: [String] = []
        for pattern in candidatePatterns {
            candidates.append(contentsOf: matches(for: pattern, in: cleanedHTML).map(normalize))
        }

        candidates.append(normalize(fallbackTitle))

        return bestCandidate(from: candidates)
    }

    private static func matches(for pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[matchRange])
        }
    }

    private static func normalize(_ text: String) -> String {
        PromptRenderer.stripHTML(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bestCandidate(from candidates: [String]) -> String? {
        let scored = candidates
            .map { ($0, score(for: $0)) }
            .filter { !$0.0.isEmpty && $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.count > rhs.0.count
            }

        return scored.first?.0
    }

    private static func score(for text: String) -> Int {
        guard looksLikeLiveSummary(text) else { return 0 }

        let normalized = text.lowercased()
        let genericTitles: Set<String> = [
            "live cricket score",
            "cricket schedule",
            "scorecard",
            "full commentary",
            "news",
            "cricbuzz",
            "current matches",
            "live",
            "recent",
            "upcoming",
            "more news",
            "more videos",
            "cricbuzz home"
        ]

        if genericTitles.contains(normalized) {
            return -1
        }

        var score = 1

        if normalized.contains(" vs ") && normalized.contains(" - ") {
            score += 120
        }
        if normalized.contains("need ") || normalized.contains("won by ") {
            score += 60
        }
        if normalized.contains("preview")
            || normalized.contains("toss")
            || normalized.contains("stumps")
            || normalized.contains("lunch")
            || normalized.contains("tea")
            || normalized.contains("live")
            || normalized.contains("complete")
            || normalized.contains("opt to bat")
            || normalized.contains("opt to bowl") {
            score += 30
        }
        if normalized.range(of: #"\b\d{1,3}/\d\b"#, options: .regularExpression) != nil {
            score += 40
        }
        if normalized.contains("match") {
            score += 10
        }

        return score + min(text.count / 12, 20)
    }

    private static func looksLikeLiveSummary(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let liveSummaryPhrases = [
            "need ",
            "won by ",
            "preview",
            "match tied",
            "no result",
            "stumps",
            "lunch",
            "tea",
            "today's match scorecard",
            "live commentary",
            "opt to bat",
            "opt to bowl",
            "toss",
            "complete"
        ]

        if liveSummaryPhrases.contains(where: normalized.contains) {
            return true
        }

        if normalized.contains(" vs ") && normalized.contains(" - ") {
            return true
        }

        return normalized.range(of: #"\b\d{1,3}/\d\b"#, options: .regularExpression) != nil
    }
}

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
        let organic = LiveOrganicSnippetExtractor.prioritize(result.organic ?? [], query: query)

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

        if let snippetAnswer = LiveOrganicSnippetExtractor.extractAnswer(from: organic, query: query) {
            return snippetAnswer
        }

        if let livePageSummary = await fetchLivePageSummary(from: organic, query: query) {
            return livePageSummary
        }

        let sourceList = organic.prefix(3).map(\.title).joined(separator: ", ")
        return "The search results point to live pages such as \(sourceList), but they do not expose the exact live value in the returned snippet."
    }

    private func fetchLivePageSummary(from organic: [SerperOrganicResult], query: String) async -> String? {
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

                if let summary = structuredLiveSummary(from: html, sourceURL: url, query: query) {
                    return summary
                }

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

    private func structuredLiveSummary(from html: String, sourceURL: URL, query: String) -> String? {
        let host = sourceURL.host?.lowercased() ?? ""

        if host.contains("cricbuzz") {
            return CricbuzzLiveMatchExtractor.extractSummary(from: html, query: query)
        }

        return nil
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

struct SerperOrganicResult: Decodable {
    let title: String
    let link: String
    let snippet: String?
}

enum LiveOrganicSnippetExtractor {
    static func prioritize(_ organic: [SerperOrganicResult], query: String) -> [SerperOrganicResult] {
        guard SearchResultFallbackComposer.queryLooksLive(query) else { return organic }

        return organic.sorted { lhs, rhs in
            let lhsScore = score(for: lhs, query: query)
            let rhsScore = score(for: rhs, query: query)
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.title < rhs.title
        }
    }

    static func extractAnswer(from organic: [SerperOrganicResult], query: String) -> String? {
        guard SearchResultFallbackComposer.queryLooksLive(query) else { return nil }

        let ranked = organic
            .compactMap { item -> (text: String, score: Int)? in
                guard let snippet = item.snippet else { return nil }
                let normalized = normalize(snippet)
                let score = score(for: item, normalizedSnippet: normalized, query: query)
                guard score >= 70 else { return nil }
                return (normalized, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.text.count > rhs.text.count
            }

        return ranked.first?.text
    }

    private static func score(for item: SerperOrganicResult, query: String) -> Int {
        score(for: item, normalizedSnippet: normalize(item.snippet ?? ""), query: query)
    }

    private static func score(for item: SerperOrganicResult, normalizedSnippet: String, query: String) -> Int {
        let normalizedTitle = normalize(item.title).lowercased()
        let combined = "\(normalizedTitle) \(normalizedSnippet.lowercased())"
        var score = 0

        if normalizedTitle.contains("live") { score += 12 }
        if normalizedTitle.contains("score") { score += 12 }
        if combined.contains("ipl") { score += 18 }
        if normalizedSnippet.range(of: #"\b\d{1,3}/\d{1,2}\b"#, options: .regularExpression) != nil {
            score += 65
        }
        if normalizedSnippet.lowercased().contains("target") {
            score += 18
        }
        if normalizedSnippet.lowercased().contains(" ov") || normalizedSnippet.lowercased().contains("/20 ov") {
            score += 14
        }

        let genericPhrases = [
            "catch the fastest live cricket scores",
            "catch up on the latest",
            "find latest scores",
            "score updates and commentary",
            "all global"
        ]
        if genericPhrases.contains(where: normalizedSnippet.lowercased().contains) {
            score -= 28
        }

        if normalizedSnippet.lowercased().contains("finished") {
            score -= 14
        }
        if query.lowercased().contains("current") || query.lowercased().contains("live") {
            if item.link.contains("espn.com/cricket/scores") {
                score += 10
            }
        }

        return score
    }

    private static func normalize(_ text: String) -> String {
        var normalized = PromptRenderer.stripHTML(text)
            .replacingOccurrences(of: "•", with: ";")
            .replacingOccurrences(of: "·", with: ";")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        normalized = normalized.replacingOccurrences(
            of: #"([a-z])([A-Z]{2,4})([.,])"#,
            with: "$1 ($2)$3",
            options: .regularExpression
        )
        normalized = normalized.replacingOccurrences(of: "\\s*;\\s*", with: "; ", options: .regularExpression)

        return normalized
    }
}

private struct CricbuzzMatchesList: Decodable {
    let matches: [CricbuzzWrappedMatch]
}

private struct CricbuzzWrappedMatch: Decodable {
    let match: CricbuzzMatchPayload
}

private struct CricbuzzMatchPayload: Decodable {
    let matchInfo: CricbuzzMatchInfo
    let matchScore: CricbuzzMatchScore?
}

private struct CricbuzzMatchInfo: Decodable {
    let seriesName: String
    let matchDesc: String
    let state: String?
    let status: String?
    let stateTitle: String?
    let team1: CricbuzzTeam
    let team2: CricbuzzTeam
}

private struct CricbuzzTeam: Decodable {
    let teamName: String
    let teamSName: String?
}

private struct CricbuzzMatchScore: Decodable {
    let team1Score: CricbuzzTeamScore?
    let team2Score: CricbuzzTeamScore?
}

private struct CricbuzzTeamScore: Decodable {
    let inngs1: CricbuzzInnings?
    let inngs2: CricbuzzInnings?
}

private struct CricbuzzInnings: Decodable {
    let runs: Int?
    let wickets: Int?
    let overs: Double?
}

enum CricbuzzLiveMatchExtractor {
    static func extractSummary(from html: String, query: String) -> String? {
        let matches = extractMatches(from: html)
        guard !matches.isEmpty else { return nil }
        guard let bestMatch = bestMatch(for: query, matches: matches) else { return nil }
        return summarize(bestMatch)
    }

    private static func extractMatches(from html: String) -> [CricbuzzMatchPayload] {
        let marker = #"matchesList\":{"#
        var matches: [CricbuzzMatchPayload] = []
        var searchStart = html.startIndex

        while let range = html.range(of: marker, range: searchStart..<html.endIndex) {
            let objectStart = html.index(before: range.upperBound)
            guard let objectEnd = balancedObjectEnd(in: html, startingAt: objectStart) else {
                break
            }

            let rawObject = String(html[objectStart...objectEnd])
            let normalized = rawObject.replacingOccurrences(of: #"\""#, with: #"""#)

            if let data = normalized.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(CricbuzzMatchesList.self, from: data) {
                matches.append(contentsOf: decoded.matches.map(\.match))
            }

            searchStart = html.index(after: objectEnd)
        }

        return matches
    }

    private static func balancedObjectEnd(in text: String, startingAt start: String.Index) -> String.Index? {
        var depth = 0
        var index = start

        while index < text.endIndex {
            let character = text[index]

            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func bestMatch(for query: String, matches: [CricbuzzMatchPayload]) -> CricbuzzMatchPayload? {
        let normalizedQuery = query.lowercased()
        let keywords = queryKeywords(from: normalizedQuery)

        return matches.max { lhs, rhs in
            score(lhs, normalizedQuery: normalizedQuery, keywords: keywords)
                < score(rhs, normalizedQuery: normalizedQuery, keywords: keywords)
        }
    }

    private static func score(_ match: CricbuzzMatchPayload, normalizedQuery: String, keywords: [String]) -> Int {
        let info = match.matchInfo
        let searchableText = [
            info.seriesName,
            info.matchDesc,
            info.status ?? "",
            info.stateTitle ?? "",
            info.team1.teamName,
            info.team1.teamSName ?? "",
            info.team2.teamName,
            info.team2.teamSName ?? ""
        ]
            .joined(separator: " ")
            .lowercased()

        var score = 0

        for keyword in keywords where searchableText.contains(keyword) {
            score += 12
        }

        if normalizedQuery.contains("ipl") && searchableText.contains("indian premier league") {
            score += 40
        }
        if normalizedQuery.contains("current") || normalizedQuery.contains("live") || normalizedQuery.contains("today") {
            switch info.state?.lowercased() {
            case "live":
                score += 30
            case "complete":
                score += 14
            default:
                break
            }
            if info.stateTitle?.lowercased().contains("preview") == true {
                score -= 20
            }
        }

        if match.matchScore?.team1Score != nil || match.matchScore?.team2Score != nil {
            score += 20
        }
        if let status = info.status, !status.isEmpty {
            score += 12
        }

        return score
    }

    private static func queryKeywords(from query: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "a", "an", "for", "and", "with", "that", "this", "from", "show",
            "give", "score", "scorecard", "match", "current", "live", "today", "now"
        ]

        return query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .map { $0.lowercased() }
            .filter { !stopWords.contains($0) }
    }

    private static func summarize(_ match: CricbuzzMatchPayload) -> String {
        let info = match.matchInfo
        let matchup = "\(info.team1.teamName) vs \(info.team2.teamName), \(info.matchDesc)"

        var scoreParts: [String] = []
        if let team1 = format(team: info.team1, score: match.matchScore?.team1Score) {
            scoreParts.append(team1)
        }
        if let team2 = format(team: info.team2, score: match.matchScore?.team2Score) {
            scoreParts.append(team2)
        }

        var summary = matchup
        if !scoreParts.isEmpty {
            summary += ": " + scoreParts.joined(separator: "; ") + "."
        }

        if let status = normalized(info.status), !status.isEmpty {
            summary += " " + status
        } else if let stateTitle = normalized(info.stateTitle), !stateTitle.isEmpty {
            summary += " " + stateTitle
        }

        return summary
    }

    private static func format(team: CricbuzzTeam, score: CricbuzzTeamScore?) -> String? {
        let innings = [score?.inngs1, score?.inngs2]
            .compactMap { $0 }
            .compactMap(format)

        guard !innings.isEmpty else { return nil }
        return "\(team.teamName) " + innings.joined(separator: " & ")
    }

    private static func format(_ innings: CricbuzzInnings) -> String? {
        guard let runs = innings.runs else { return nil }

        var formatted = "\(runs)"
        if let wickets = innings.wickets {
            formatted += "/\(wickets)"
        }
        if let overs = innings.overs {
            formatted += " (\(formatOvers(overs)) ov)"
        }

        return formatted
    }

    private static func formatOvers(_ overs: Double) -> String {
        if overs.rounded(.down) == overs {
            return String(Int(overs))
        }
        return String(format: "%.1f", overs)
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
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

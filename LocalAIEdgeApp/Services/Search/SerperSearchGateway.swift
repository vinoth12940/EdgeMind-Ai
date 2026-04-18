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

        let answerText = primaryAnswerText(from: result, organic: organic, query: query)

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

    private func primaryAnswerText(from result: SerperResponse, organic: [SerperOrganicResult], query: String) -> String? {
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

        let sourceList = organic.prefix(3).map(\.title).joined(separator: ", ")
        return "The search results point to live pages such as \(sourceList), but they do not expose the exact live value in the returned snippet."
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

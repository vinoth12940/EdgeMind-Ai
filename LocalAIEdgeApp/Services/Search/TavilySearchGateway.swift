import Foundation

struct TavilySearchGateway: SearchGateway {
    let apiKey: String

    func search(query: String) async throws -> SearchContext {
        guard !apiKey.isEmpty else {
            throw SearchGatewayError.invalidAPIKey(provider: "Tavily")
        }

        var request = URLRequest(url: URL(string: "https://api.tavily.com/search")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "api_key": apiKey,
            "query": query,
            "max_results": 5,
            "include_answer": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SearchGatewayError.httpError(statusCode: code, provider: "Tavily")
        }

        let result = try JSONDecoder().decode(TavilyResponse.self, from: data)

        let snippets = result.results.prefix(5).map { Self.stripHTML($0.content) }
        if let answer = result.answer, !answer.isEmpty {
            return SearchContext(
                query: query,
                snippets: [Self.stripHTML(answer)] + snippets,
                citations: result.results.prefix(5).map { item in
                    SearchCitation(
                        title: Self.stripHTML(item.title),
                        url: URL(string: item.url) ?? URL(string: "https://tavily.com")!,
                        snippet: String(Self.stripHTML(item.content).prefix(200))
                    )
                }
            )
        }

        return SearchContext(
            query: query,
            snippets: Array(snippets),
            citations: result.results.prefix(5).map { item in
                SearchCitation(
                    title: Self.stripHTML(item.title),
                    url: URL(string: item.url) ?? URL(string: "https://tavily.com")!,
                    snippet: String(Self.stripHTML(item.content).prefix(200))
                )
            }
        )
    }

    private static func stripHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

// MARK: - Tavily API Models

private struct TavilyResponse: Decodable {
    let answer: String?
    let results: [TavilyResult]
}

private struct TavilyResult: Decodable {
    let title: String
    let url: String
    let content: String
}

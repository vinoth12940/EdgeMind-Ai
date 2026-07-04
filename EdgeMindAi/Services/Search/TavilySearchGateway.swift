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
            "include_answer": true,
            "search_depth": "advanced",
            "include_raw_content": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SearchGatewayError.httpError(statusCode: code, provider: "Tavily")
        }

        let result = try JSONDecoder().decode(TavilyResponse.self, from: data)

        // Diagnostic logging - see what Tavily returns
        print("[TAVILY DEBUG] Query: \(query)")
        print("[TAVILY DEBUG] Answer present: \(result.answer != nil), Answer: \(result.answer?.prefix(150) ?? "nil")")
        print("[TAVILY DEBUG] Results count: \(result.results.count)")
        for (i, item) in result.results.prefix(3).enumerated() {
            print("[TAVILY DEBUG] Result[\(i)]: content=\(item.content.count) chars")
        }

        let snippets = result.results.prefix(5).map { item -> String in
            let body = item.content
            return "\(Self.stripHTML(item.title)): \(Self.stripHTML(body))"
        }
        let answerText: String? = {
            guard let answer = result.answer, !answer.isEmpty else { return nil }
            return Self.stripHTML(answer)
        }()

        print("[TAVILY DEBUG] Final: answer=\(answerText != nil ? "✓(\(answerText!.count) chars)" : "nil"), snippets count=\(snippets.count)")

        return SearchContext(
            query: query,
            answer: answerText,
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
    let raw_content: String?
}

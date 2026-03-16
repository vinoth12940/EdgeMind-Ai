import Foundation

struct SerperSearchGateway: SearchGateway {
    let apiKey: String

    func search(query: String) async throws -> SearchContext {
        guard !apiKey.isEmpty else {
            throw SearchGatewayError.endpointUnavailable
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
            throw SearchGatewayError.endpointUnavailable
        }

        let result = try JSONDecoder().decode(SerperResponse.self, from: data)
        let organic = result.organic ?? []

        var snippets: [String] = []
        if let answer = result.answerBox?.answer ?? result.answerBox?.snippet {
            snippets.append(answer)
        }
        snippets += organic.prefix(5).compactMap { $0.snippet }

        return SearchContext(
            query: query,
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
}

// MARK: - Serper API Models

private struct SerperResponse: Decodable {
    let answerBox: SerperAnswerBox?
    let organic: [SerperOrganicResult]?
}

private struct SerperAnswerBox: Decodable {
    let answer: String?
    let snippet: String?
}

private struct SerperOrganicResult: Decodable {
    let title: String
    let link: String
    let snippet: String?
}

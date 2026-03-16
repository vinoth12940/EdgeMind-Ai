import Foundation

struct BraveSearchGateway: SearchGateway {
    let apiKey: String

    func search(query: String) async throws -> SearchContext {
        guard !apiKey.isEmpty else {
            throw SearchGatewayError.endpointUnavailable
        }

        var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: "5")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw SearchGatewayError.endpointUnavailable
        }

        let result = try JSONDecoder().decode(BraveResponse.self, from: data)
        let webResults = result.web?.results ?? []

        return SearchContext(
            query: query,
            snippets: webResults.prefix(5).map { $0.description },
            citations: webResults.prefix(5).map { item in
                SearchCitation(
                    title: item.title,
                    url: URL(string: item.url) ?? URL(string: "https://brave.com")!,
                    snippet: String(item.description.prefix(200))
                )
            }
        )
    }
}

// MARK: - Brave API Models

private struct BraveResponse: Decodable {
    let web: BraveWebResults?
}

private struct BraveWebResults: Decodable {
    let results: [BraveWebResult]
}

private struct BraveWebResult: Decodable {
    let title: String
    let url: String
    let description: String
}

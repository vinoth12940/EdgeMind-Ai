import Foundation

/// Calls a user-provided gateway URL with a POST JSON body containing the query.
struct CustomSearchGateway: SearchGateway {
    let gatewayURL: URL

    func search(query: String) async throws -> SearchContext {
        var request = URLRequest(url: gatewayURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["query": query]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SearchGatewayError.httpError(statusCode: code, provider: "Custom Gateway")
        }

        return try JSONDecoder().decode(SearchContext.self, from: data)
    }
}

// MARK: - Factory

enum SearchGatewayFactory {
    static func make(settings: AppSettings) -> SearchGateway? {
        switch settings.webSearchProvider {
        case .none:
            return nil
        case .tavily:
            guard !settings.webSearchAPIKey.isEmpty else { return nil }
            return TavilySearchGateway(apiKey: settings.webSearchAPIKey)
        case .brave:
            guard !settings.webSearchAPIKey.isEmpty else { return nil }
            return BraveSearchGateway(apiKey: settings.webSearchAPIKey)
        case .serper:
            guard !settings.webSearchAPIKey.isEmpty else { return nil }
            return SerperSearchGateway(apiKey: settings.webSearchAPIKey)
        case .custom:
            guard let url = settings.searchGatewayURL else { return nil }
            return CustomSearchGateway(gatewayURL: url)
        }
    }
}

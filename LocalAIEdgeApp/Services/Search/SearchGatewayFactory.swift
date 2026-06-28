import Foundation

/// Calls a user-provided gateway URL with a POST JSON body containing the query.
struct CustomSearchGateway: SearchGateway {
    let gatewayURL: URL

    func search(query: String) async throws -> SearchContext {
        var request = URLRequest(url: Self.normalizedEndpoint(from: gatewayURL))
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

    static func normalizedEndpoint(from gatewayURL: URL) -> URL {
        guard var components = URLComponents(url: gatewayURL, resolvingAgainstBaseURL: false) else {
            return gatewayURL
        }

        switch components.path {
        case "", "/":
            components.path = "/api/search"
        case "/health":
            components.path = "/api/search"
        default:
            break
        }

        return components.url ?? gatewayURL
    }
}

// MARK: - Factory

enum SearchGatewayFactory {
    static func make(settings: AppSettings) -> SearchGateway? {
        switch settings.webSearchProvider {
        case .none:
            guard let url = normalizedCustomGatewayURL(from: settings) else { return nil }
            return CustomSearchGateway(gatewayURL: url)
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
            guard let url = normalizedCustomGatewayURL(from: settings) else { return nil }
            return CustomSearchGateway(gatewayURL: url)
        }
    }

    static func shouldAutoEnableLiveSearch(settings: AppSettings) -> Bool {
        settings.useSearchByDefault && make(settings: settings) != nil
    }

    static func hasSuggestedGateway(settings: AppSettings) -> Bool {
        normalizedCustomGatewayURL(from: settings) != nil
    }

    private static func normalizedCustomGatewayURL(from settings: AppSettings) -> URL? {
        guard let url = settings.searchGatewayURL else { return nil }
        let absolute = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !absolute.isEmpty else { return nil }
        return CustomSearchGateway.normalizedEndpoint(from: url)
    }
}

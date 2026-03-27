import Foundation

protocol SearchGateway {
    func search(query: String) async throws -> SearchContext
}

enum SearchGatewayError: LocalizedError {
    case endpointUnavailable
    case httpError(statusCode: Int, provider: String)
    case invalidAPIKey(provider: String)

    var errorDescription: String? {
        switch self {
        case .endpointUnavailable:
            return "Search endpoint unreachable. Check your network or backend URL."
        case .httpError(let code, let provider):
            if code == 401 || code == 403 {
                return "\(provider): Invalid API key (HTTP \(code)). Check Settings → Web Search API."
            } else if code == 429 {
                return "\(provider): Rate limit exceeded (HTTP 429). Try again shortly."
            }
            return "\(provider): Request failed (HTTP \(code))."
        case .invalidAPIKey(let provider):
            return "\(provider): API key is missing or invalid."
        }
    }
}

struct MockSearchGateway: SearchGateway {
    func search(query: String) async throws -> SearchContext {
        try await Task.sleep(for: .milliseconds(220))

        return SearchContext(
            query: query,
            snippets: [
                "Fresh search result summary for: \(query).",
                "Use a small backend to protect the search provider API key.",
                "Show the user which parts of a response are grounded in live web data."
            ],
            citations: MockCatalogData.citations
        )
    }
}

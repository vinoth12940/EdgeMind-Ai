import Foundation

protocol SearchGateway {
    func search(query: String) async throws -> SearchContext
}

enum SearchGatewayError: LocalizedError {
    case endpointUnavailable

    var errorDescription: String? {
        switch self {
        case .endpointUnavailable:
            return "Live Search is unavailable. Start the search gateway or update the backend URL in settings."
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

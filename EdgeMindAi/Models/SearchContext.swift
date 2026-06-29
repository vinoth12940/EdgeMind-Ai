import Foundation

struct SearchContext: Hashable, Codable {
    let query: String
    /// Pre-summarized answer from the search provider (e.g. Tavily answer, Serper answerBox).
    /// Nil when the provider doesn't offer one.
    let answer: String?
    let snippets: [String]
    let citations: [SearchCitation]

    init(query: String, answer: String? = nil, snippets: [String], citations: [SearchCitation]) {
        self.query = query
        self.answer = answer
        self.snippets = snippets
        self.citations = citations
    }
}

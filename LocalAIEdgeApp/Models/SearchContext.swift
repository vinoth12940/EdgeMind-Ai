import Foundation

struct SearchContext: Hashable, Codable {
    let query: String
    let snippets: [String]
    let citations: [SearchCitation]
}

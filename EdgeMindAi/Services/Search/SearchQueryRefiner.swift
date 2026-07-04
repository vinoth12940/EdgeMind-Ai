import Foundation

struct SearchQueryRefiner {
    /// Refines a search query by injecting missing key subject terms from previous turns of the conversation history.
    /// This prevents short follow-up prompts (e.g. "give me full scorecard") from searching for generic or incorrect topics.
    static func refine(_ query: String, conversation: [ChatMessage]) -> String {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var baselineQuery = trimmedQuery
        
        // Find all previous user messages
        let userMessages = conversation.filter { $0.role == .user }
        if !userMessages.isEmpty {
            // Extract potential subject words (proper nouns or key nouns) from previous user messages
            // We will scan backwards to find the most recent topic.
            var contextKeywords: [String] = []
            
            // Stop words and generic queries to avoid appending
            let stopWords: Set<String> = [
                "what", "where", "when", "who", "whom", "which", "whose", "why", "how",
                "give", "show", "tell", "please", "about", "score", "scorecard", "scare", "card",
                "the", "and", "for", "with", "this", "that", "there", "their", "they", "them",
                "your", "mine", "some", "more", "full", "here", "there", "info", "data", "result",
                "results", "give me", "show me", "tell me", "what is", "who is", "how to", "is", "are", "was",
                "were", "be", "been", "being", "have", "has", "had", "do", "does", "did", "a", "an", "the",
                "of", "in", "on", "at", "by", "to", "from", "up", "down", "out", "over", "under", "again",
                "further", "then", "once", "here", "there", "when", "where", "why", "how", "all", "any",
                "both", "each", "few", "more", "most", "other", "some", "such", "no", "nor", "not", "only",
                "own", "same", "so", "than", "too", "very", "can", "will", "just", "should", "now", "me", "give me"
            ]
            
            for msg in userMessages.suffix(3).reversed() {
                // Tokenize text into words
                let words = msg.text.components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.count >= 2 } // ignore single letters/empty space
                
                for word in words {
                    let lower = word.lowercased()
                    if !stopWords.contains(lower) {
                        if !contextKeywords.contains(lower) {
                            contextKeywords.append(lower)
                        }
                    }
                }
            }
            
            // Now inspect the new query words
            let newQueryWords = trimmedQuery.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            
            // Find which keywords from the previous context are NOT in the new query
            let missingContextKeywords = contextKeywords.filter { keyword in
                !newQueryWords.contains { newWord in
                    newWord.contains(keyword) || keyword.contains(newWord)
                }
            }
            
            // Filter out generic stop words from the new query to see if it has specific subject content
            let specificNewWords = newQueryWords.filter { !stopWords.contains($0) }
            
            // If the query contains little or no specific subject nouns (e.g. <= 1 specific word)
            // and we have missing context keywords, we inject the context keywords.
            if specificNewWords.count <= 1 && !missingContextKeywords.isEmpty {
                // We append the top 3 missing context keywords
                let contextToAppend = missingContextKeywords.prefix(3).joined(separator: " ")
                baselineQuery = "\(trimmedQuery) \(contextToAppend)"
                print("[SEARCH REFINER] Reformulated context: added '\(contextToAppend)' (specific words count: \(specificNewWords.count))")
            }
        }
        
        let finalQuery = appendCurrentYearIfTimeSensitive(baselineQuery)
        print("[SEARCH REFINER] Input: '\(trimmedQuery)', Output: '\(finalQuery)'")
        return finalQuery
    }

    private static func appendCurrentYearIfTimeSensitive(_ query: String) -> String {
        let lower = query.lowercased()
        
        // If it already contains a year (e.g. 2024, 2025, 2026), don't override
        let hasYear = lower.range(of: #"\\b(19|20)\\d{2}\\b"#, options: .regularExpression) != nil
        if hasYear {
            return query
        }
        
        // Time-sensitive words that warrant adding the current year
        let timeSensitiveWords = [
            "score", "scorecard", "match", "game", "vs", "cup", "tournament", "series",
            "standing", "standings", "ranking", "rankings", "playoff", "playoffs", "live",
            "current", "latest", "today", "yesterday", "result", "results", "news"
        ]
        
        let needsYear = timeSensitiveWords.contains { word in
            lower.contains(word)
        }
        
        if needsYear {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy"
            let year = formatter.string(from: Date())
            return "\(query) \(year)"
        }
        
        return query
    }
}

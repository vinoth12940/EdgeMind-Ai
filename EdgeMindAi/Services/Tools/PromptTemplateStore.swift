// LocalAIEdgeApp/Services/Tools/PromptTemplateStore.swift
import Foundation
import OSLog

private let logger = Logger(subsystem: "io.example.PrivateEdgeChat", category: "PromptTemplateStore")

/// Loads the bundled `PromptTemplates.json` once and exposes the template list.
/// Mirrors `RuntimeProfileStore`: a dependency-injected bundle loader for testability,
/// graceful fallback to an empty list if the file is missing or malformed.
///
/// v0.2.0 is read-only — there is no override or persistence path. User-created
/// templates are a future feature.
final class PromptTemplateStore {

    let templates: [PromptTemplate]

    init(bundleLoader: (() -> [PromptTemplate])? = nil) {
        let loaded = (bundleLoader ?? Self.loadBundled)()
        self.templates = loaded.sorted { lhs, rhs in
            if lhs.category != rhs.category { return lhs.category < rhs.category }
            return lhs.title < rhs.title
        }
    }

    /// Templates grouped by category, in display order. Drives the Prompt Library UI.
    var grouped: [(category: String, templates: [PromptTemplate])] {
        let order = templates.reduce(into: [String]()) { acc, t in
            if !acc.contains(t.category) { acc.append(t.category) }
        }
        return order.map { cat in
            (cat, templates.filter { $0.category == cat })
        }
    }

    static func loadBundled() -> [PromptTemplate] {
        guard let url = Bundle.main.url(forResource: "PromptTemplates", withExtension: "json") else {
            logger.error("PromptTemplates.json missing from bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([PromptTemplate].self, from: data)
        } catch {
            logger.error("Failed to decode PromptTemplates.json: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}

// LocalAIEdgeApp/Models/PromptTemplate.swift
import Foundation

/// A reusable prompt template surfaced in the composer's Prompt Library.
///
/// v0.2.0 ships built-in templates only (bundled in `PromptTemplates.json`, loaded by
/// `PromptTemplateStore`). The shape leaves room for user-created templates later:
/// fields are Codable and use `decodeIfPresent` defaults so a future UserDefaults
/// persistence layer can round-trip the same struct.
struct PromptTemplate: Identifiable, Hashable, Codable {
    let id: UUID
    let slug: String
    let title: String
    let body: String
    let category: String
    let icon: String          // SF Symbol name
    let requiredCapability: String?   // e.g. "vision" — reserved for future gating

    private enum CodingKeys: String, CodingKey {
        case id, slug, title, body, category, icon, requiredCapability
    }

    init(id: UUID? = nil,
         slug: String,
         title: String,
         body: String,
         category: String,
         icon: String,
         requiredCapability: String? = nil) {
        self.id = id ?? Self.deterministicID(slug: slug, category: category)
        self.slug = slug
        self.title = title
        self.body = body
        self.category = category
        self.icon = icon
        self.requiredCapability = requiredCapability
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Allow the JSON to omit `id`; fall back to the deterministic v5 value.
        if let provided = try c.decodeIfPresent(UUID.self, forKey: .id) {
            self.id = provided
        } else {
            let slug = try c.decode(String.self, forKey: .slug)
            let category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
            self.id = Self.deterministicID(slug: slug, category: category)
        }
        self.slug = try c.decode(String.self, forKey: .slug)
        self.title = try c.decode(String.self, forKey: .title)
        self.body = try c.decode(String.self, forKey: .body)
        self.category = try c.decodeIfPresent(String.self, forKey: .category) ?? "General"
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "text.bubble"
        self.requiredCapability = try c.decodeIfPresent(String.self, forKey: .requiredCapability)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(slug, forKey: .slug)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(category, forKey: .category)
        try c.encode(icon, forKey: .icon)
        try c.encodeIfPresent(requiredCapability, forKey: .requiredCapability)
    }

    /// Stable UUID v5 so a template keeps its identity across launches and JSON edits
    /// (as long as slug + category are unchanged).
    static func deterministicID(slug: String, category: String) -> UUID {
        DeterministicID.uuidV5(namespace: DeterministicID.promptTemplateNamespace,
                               name: "\(slug)::\(category)")
    }
}

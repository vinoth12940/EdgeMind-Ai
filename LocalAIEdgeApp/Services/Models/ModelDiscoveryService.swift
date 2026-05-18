import Foundation

struct ModelDiscoveryCandidate: Identifiable, Hashable {
    enum Compatibility: String, Hashable {
        case mlxLLM
        case mlxVLM
        case ggufText
        case experimental
    }

    let id: String
    let displayName: String
    let modelID: String
    let compatibility: Compatibility
    let downloads: Int
    let tags: [String]

    var isInstallable: Bool {
        compatibility != .experimental
    }
}

protocol ModelDiscoveryService {
    func search(query: String) async throws -> [ModelDiscoveryCandidate]
}

struct HuggingFaceModelDiscoveryService: ModelDiscoveryService {
    private struct HFModel: Decodable {
        let id: String
        let downloads: Int?
        let tags: [String]?
        let pipeline_tag: String?
    }

    func search(query: String) async throws -> [ModelDiscoveryCandidate] {
        var components = URLComponents(string: "https://huggingface.co/api/models")!
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "25")
        ]
        let url = components.url!
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        let models = try JSONDecoder().decode([HFModel].self, from: data)
        return models.map(Self.normalize(_:))
    }

    private static func normalize(_ model: HFModel) -> ModelDiscoveryCandidate {
        let tags = model.tags ?? []
        let lowerID = model.id.lowercased()
        let lowerTags = tags.map { $0.lowercased() }
        let compatibility: ModelDiscoveryCandidate.Compatibility

        if lowerID.contains("mlx") || lowerID.contains("mlx-community") || lowerTags.contains("mlx") {
            if lowerTags.contains("image-text-to-text")
                || lowerTags.contains("vision-language-model")
                || lowerTags.contains("mlx-vlm")
                || lowerID.contains("vl") {
                compatibility = .mlxVLM
            } else {
                compatibility = .mlxLLM
            }
        } else if lowerID.contains("gguf") || lowerTags.contains("gguf") {
            compatibility = .ggufText
        } else {
            compatibility = .experimental
        }

        return ModelDiscoveryCandidate(
            id: model.id,
            displayName: model.id.split(separator: "/").last.map(String.init) ?? model.id,
            modelID: model.id,
            compatibility: compatibility,
            downloads: model.downloads ?? 0,
            tags: tags
        )
    }
}

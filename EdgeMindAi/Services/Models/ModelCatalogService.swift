import Foundation

protocol ModelCatalogService {
    func fetchCatalog() async throws -> [ModelCatalogItem]
}

struct MockModelCatalogService: ModelCatalogService {
    func fetchCatalog() async throws -> [ModelCatalogItem] {
        try await Task.sleep(for: .milliseconds(120))
        return MockCatalogData.items
    }
}

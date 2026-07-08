// LocalAIEdgeApp/Models/DeterministicID.swift
import Foundation
import CommonCrypto

/// Stable UUID v5 generation shared across bundled entities (catalog items,
/// tools, prompt templates). Each entity type gets its own namespace so IDs
/// can never collide even if two entities happen to share a name.
enum DeterministicID {

    // Distinct namespaces per entity type.
    static let modelCatalogNamespace = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
    static let toolNamespace         = UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F23456789012")!
    static let promptTemplateNamespace = UUID(uuidString: "C3D4E5F6-A7B8-9012-CDEF-345678901234")!

    /// UUID v5 (SHA-1 namespaced) from a name string.
    static func uuidV5(namespace: UUID, name: String) -> UUID {
        let namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        let nameBytes = Array(name.utf8)
        let data = namespaceBytes + nameBytes

        var hash = [UInt8](repeating: 0, count: 20)
        data.withUnsafeBufferPointer { ptr in
            var ctx = CC_SHA1_CTX()
            CC_SHA1_Init(&ctx)
            CC_SHA1_Update(&ctx, ptr.baseAddress, CC_LONG(ptr.count))
            CC_SHA1_Final(&hash, &ctx)
        }
        // Set version (5) and variant bits.
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80

        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3],
                           hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11],
                           hash[12], hash[13], hash[14], hash[15]))
    }
}

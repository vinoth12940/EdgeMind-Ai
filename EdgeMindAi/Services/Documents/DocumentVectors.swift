import Foundation

/// Memory-mapped reader/writer for a document's vectors.
///
/// File layout (little-endian):
/// `dimension: UInt32`, `count: UInt32`, `kind: UInt8`, then `count × dimension`
/// `Float32` rows. Reading uses `Data(contentsOf:options:.alwaysMapped)` so the
/// in-memory footprint does not grow with the library (spec §3).
struct DocumentVectors {
    let kind: DocumentEmbeddingKind
    let dimension: Int
    let count: Int

    private let storage: Data
    private let rowsOffset: Int

    static let headerByteCount = 9

    init(kind: DocumentEmbeddingKind, dimension: Int, vectors: [[Float]]) {
        self.kind = kind
        self.dimension = dimension
        self.count = vectors.count
        self.rowsOffset = Self.headerByteCount

        var data = Data(capacity: Self.headerByteCount + vectors.count * dimension * 4)
        data.appendLittleEndian(UInt32(dimension))
        data.appendLittleEndian(UInt32(vectors.count))
        data.append(Self.tag(for: kind))
        for row in vectors {
            for value in row.prefix(dimension) {
                data.appendLittleEndian(value.bitPattern)
            }
        }
        self.storage = data
    }

    init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped),
              data.count >= Self.headerByteCount else { return nil }

        let dimension = Int(data.readLittleEndianUInt32(at: 0))
        let count = Int(data.readLittleEndianUInt32(at: 4))
        let kind = Self.kind(for: data[data.startIndex + 8])
        guard dimension > 0, count >= 0 else { return nil }

        // Guard the arithmetic: a corrupt header can hold UInt32.max in both fields,
        // and `count * dimension * 4` would TRAP (crash) instead of failing this
        // failable initializer, taking the app down on a malformed .vectors.bin.
        let (rowBytes, rowOverflow) = count.multipliedReportingOverflow(by: dimension)
        guard !rowOverflow else { return nil }
        let (payloadBytes, byteOverflow) = rowBytes.multipliedReportingOverflow(by: 4)
        guard !byteOverflow else { return nil }
        let (expected, sumOverflow) = Self.headerByteCount.addingReportingOverflow(payloadBytes)
        guard !sumOverflow, data.count >= expected else { return nil }

        self.kind = kind
        self.dimension = dimension
        self.count = count
        self.storage = data
        self.rowsOffset = Self.headerByteCount
    }

    var isEmpty: Bool { count == 0 || dimension == 0 }

    func vector(at index: Int) -> [Float]? {
        guard index >= 0, index < count else { return nil }
        let rowOffset = rowsOffset + index * dimension * 4
        guard rowOffset + dimension * 4 <= storage.count else { return nil }

        return storage.withUnsafeBytes { raw -> [Float]? in
            guard let base = raw.baseAddress else { return nil }
            let floatPointer = base.advanced(by: rowOffset).assumingMemoryBound(to: UInt32.self)
            var row = [Float](repeating: 0, count: dimension)
            for element in 0..<dimension {
                row[element] = Float(bitPattern: UInt32(littleEndian: floatPointer[element]))
            }
            return row
        }
    }

    func write(to url: URL) throws {
        try storage.write(to: url, options: .atomic)
    }

    // MARK: - Tags

    private static func tag(for kind: DocumentEmbeddingKind) -> UInt8 {
        switch kind {
        case .contextual: return 0
        case .sentence: return 1
        case .none: return 2
        }
    }

    private static func kind(for tag: UInt8) -> DocumentEmbeddingKind {
        switch tag {
        case 0: return .contextual
        case 1: return .sentence
        default: return .none
        }
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: Float) {
        appendLittleEndian(value.bitPattern)
    }

    func readLittleEndianUInt32(at offset: Int) -> UInt32 {
        let start = startIndex + offset
        var value: UInt32 = 0
        for byte in 0..<4 {
            value |= UInt32(self[start + byte]) << (8 * byte)
        }
        return value
    }
}

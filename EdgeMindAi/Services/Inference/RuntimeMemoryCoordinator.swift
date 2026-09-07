import Foundation

enum RuntimeMemoryCoordinator {
    private static let lock = NSLock()
    private static var _activeRuntime: ModelCatalogItem.RuntimeType?

    /// The currently prepared active inference runtime, if any.
    static var activeRuntime: ModelCatalogItem.RuntimeType? {
        lock.lock()
        defer { lock.unlock() }
        return _activeRuntime
    }

    /// Prepares the system for executing inference on the requested runtime,
    /// enforcing strict mutual exclusion by completely unloading any existing runtime weights.
    static func prepareForRuntime(_ runtimeType: ModelCatalogItem.RuntimeType) async {
        switch runtimeType {
        case .gguf:
            #if canImport(MLXLLM) && !targetEnvironment(simulator)
            await MLXRuntime.shared.unloadAndClearCache()
            #endif
            #if canImport(LiteRTLM) && !targetEnvironment(simulator)
            await LiteRTRuntime.shared.unload()
            #endif
        case .mlx:
            await LocalLlamaRuntime.shared.unload()
            #if canImport(LiteRTLM) && !targetEnvironment(simulator)
            await LiteRTRuntime.shared.unload()
            #endif
        case .liteRTLM:
            await LocalLlamaRuntime.shared.unload()
            #if canImport(MLXLLM) && !targetEnvironment(simulator)
            await MLXRuntime.shared.unloadAndClearCache()
            #endif
        case .foundationModels:
            await releaseAll()
        }

        lock.lock()
        _activeRuntime = runtimeType
        lock.unlock()
    }

    static func releaseAfterAudit(_ runtimeType: ModelCatalogItem.RuntimeType) async {
        switch runtimeType {
        case .gguf:
            await LocalLlamaRuntime.shared.unload()
        case .mlx:
            #if canImport(MLXLLM) && !targetEnvironment(simulator)
            await MLXRuntime.shared.unloadAndClearCache()
            #endif
        case .liteRTLM:
            #if canImport(LiteRTLM) && !targetEnvironment(simulator)
            await LiteRTRuntime.shared.unload()
            #endif
        case .foundationModels:
            break
        }

        lock.lock()
        if _activeRuntime == runtimeType {
            _activeRuntime = nil
        }
        lock.unlock()
    }

    static func releaseAll() async {
        await LocalLlamaRuntime.shared.unload()
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        await MLXRuntime.shared.unloadAndClearCache()
        #endif
        #if canImport(LiteRTLM) && !targetEnvironment(simulator)
        await LiteRTRuntime.shared.unload()
        #endif

        lock.lock()
        _activeRuntime = nil
        lock.unlock()
    }
}

import Foundation

enum RuntimeMemoryCoordinator {
    static func prepareForRuntime(_ runtimeType: ModelCatalogItem.RuntimeType) async {
        switch runtimeType {
        case .gguf:
            #if canImport(MLXLLM) && !targetEnvironment(simulator)
            await MLXRuntime.shared.unloadAndClearCache()
            #endif
            #if canImport(LiteRTLM) && !targetEnvironment(simulator)
            await LiteRTRuntime.shared.unload()
            #endif
        case .mlx, .liteRTLM:
            await LocalLlamaRuntime.shared.unload()
            if runtimeType == .liteRTLM {
                #if canImport(MLXLLM) && !targetEnvironment(simulator)
                await MLXRuntime.shared.unloadAndClearCache()
                #endif
            }
        case .foundationModels:
            await releaseAll()
        }
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
            return
        }
    }

    static func releaseAll() async {
        await LocalLlamaRuntime.shared.unload()
        #if canImport(MLXLLM) && !targetEnvironment(simulator)
        await MLXRuntime.shared.unloadAndClearCache()
        #endif
        #if canImport(LiteRTLM) && !targetEnvironment(simulator)
        await LiteRTRuntime.shared.unload()
        #endif
    }
}

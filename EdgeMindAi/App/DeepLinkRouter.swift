import Foundation
import Observation

/// Where a URL should take the app.
enum DeepLinkRoute: Equatable {
    enum AskMode: String, Equatable {
        case text
        case voice
        case camera
    }

    case ask(mode: AskMode)
    case share(UUID)
    case settingsMemory
    case settingsDocuments
}

/// Parses `edgemindai://` URLs. Pure so every route and malformed input can be
/// unit tested (spec §5).
enum DeepLinkRouter {
    static let scheme = "edgemindai"

    static func route(for url: URL) -> DeepLinkRoute? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        switch url.host?.lowercased() {
        case "ask":
            let mode = url.queryValue(for: "mode").flatMap(DeepLinkRoute.AskMode.init(rawValue:)) ?? .text
            return .ask(mode: mode)

        case "share":
            // edgemindai://share/<uuid>
            let components = url.pathComponents.filter { $0 != "/" }
            guard let raw = components.first, let id = UUID(uuidString: raw) else { return nil }
            return .share(id)

        case "settings":
            let components = url.pathComponents.filter { $0 != "/" }
            switch components.first?.lowercased() {
            case "memory": return .settingsMemory
            case "documents": return .settingsDocuments
            default: return nil
            }

        default:
            return nil
        }
    }
}

private extension URL {
    func queryValue(for name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }
}

/// Holds the most recent deep link for the UI to consume. Created by
/// `EdgeMindAiApp` and injected into the environment.
@MainActor
@Observable
final class DeepLinkCoordinator {
    /// Settings destination requested by a deep link, if any.
    enum SettingsSection: Equatable {
        case memory
        case documents
    }

    private(set) var pendingRoute: DeepLinkRoute?
    private(set) var requestedSettingsSection: SettingsSection?

    func handle(_ url: URL) {
        guard let route = DeepLinkRouter.route(for: url) else { return }
        switch route {
        case .settingsMemory:
            requestedSettingsSection = .memory
        case .settingsDocuments:
            requestedSettingsSection = .documents
        default:
            break
        }
        pendingRoute = route
    }

    /// Returns and clears the pending route (one-shot consumption).
    func consumeRoute() -> DeepLinkRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    func consumeSettingsSection() -> SettingsSection? {
        defer { requestedSettingsSection = nil }
        return requestedSettingsSection
    }
}

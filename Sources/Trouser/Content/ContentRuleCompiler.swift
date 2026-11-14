import WebKit

enum ContentRuleError: LocalizedError {
    case storeUnavailable

    var errorDescription: String? {
        switch self {
        case .storeUnavailable: "the content rule store is unavailable"
        }
    }
}

@MainActor
enum ContentRuleCompiler {
    static func compile(_ json: String) async throws -> WKContentRuleList? {
        guard let store = WKContentRuleListStore.default() else { throw ContentRuleError.storeUnavailable }
        let identifier = ContentRules.identifier(for: json)
        if let cached = try? await store.contentRuleList(forIdentifier: identifier) {
            return cached
        }
        return try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
    }
}

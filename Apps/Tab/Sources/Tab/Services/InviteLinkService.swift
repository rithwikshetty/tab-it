import Foundation
import Observation

@MainActor
@Observable
final class InviteLinkService {
    private static let pendingTokenKey = "pendingInviteJoinToken"

    private let defaults: UserDefaults
    private(set) var pendingJoinToken: String? {
        didSet {
            if let pendingJoinToken {
                defaults.set(pendingJoinToken, forKey: Self.pendingTokenKey)
            } else {
                defaults.removeObject(forKey: Self.pendingTokenKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pendingJoinToken = defaults.string(forKey: Self.pendingTokenKey)
            .flatMap(Self.normalizedToken)
    }

    func capture(url: URL) -> Bool {
        guard let token = Self.token(from: url) else { return false }
        pendingJoinToken = token
        return true
    }

    func consumePendingToken() -> String? {
        defer { pendingJoinToken = nil }
        return pendingJoinToken
    }

    nonisolated static func token(from url: URL) -> String? {
        let token: String?
        if url.scheme?.lowercased() == "https",
           ["tab-it.app", "www.tab-it.app"].contains(url.host?.lowercased() ?? ""),
           url.pathComponents.count == 3,
           url.pathComponents[1] == "join" {
            token = url.pathComponents[2]
        } else if url.scheme?.lowercased() == SupabaseConfig.authCallbackScheme.lowercased(),
                  url.host?.lowercased() == "join",
                  url.pathComponents.count == 2 {
            token = url.pathComponents[1]
        } else {
            token = nil
        }
        return token.flatMap(normalizedToken)
    }

    private nonisolated static func normalizedToken(_ token: String) -> String? {
        let normalized = token.lowercased()
        guard normalized.utf8.count == 32,
              normalized.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else { return nil }
        return normalized
    }
}

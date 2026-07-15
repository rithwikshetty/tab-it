import AuthenticationServices
import Foundation
import Supabase

struct CurrentUser: Equatable, Sendable {
    static let privateRelayPlaceholder = "Email hidden by Apple"

    let id: UUID
    /// Verified email from Supabase Auth. This may be an Apple private relay address.
    let email: String?
    /// User-facing email. Hidden for Apple private relay addresses so we do not show random relay IDs.
    let displayEmail: String?
    let displayName: String
    let hasPrivateRelayEmail: Bool

    /// The email line to show in the UI: the real address, a placeholder for hidden Apple relays, or nil when there is nothing to show.
    var presentableEmail: String? {
        if let displayEmail { return displayEmail }
        return hasPrivateRelayEmail ? Self.privateRelayPlaceholder : nil
    }
}

@MainActor
@Observable
final class AuthService {
    nonisolated static let emailVerificationCodeLength = 8

    enum Phase: Equatable {
        case loading
        case signedOut
        case signedIn(UUID)
    }

    enum AuthInputError: LocalizedError {
        case missingName
        case invalidEmail
        case invalidCode
        case missingVerifiedSession
        case missingSupabaseConfig

        var errorDescription: String? {
            switch self {
            case .missingName:
                "Enter your full name."
            case .invalidEmail:
                "Enter a valid email address."
            case .invalidCode:
                "Enter the \(AuthService.emailVerificationCodeLength)-digit code from your email."
            case .missingVerifiedSession:
                "We verified the code but couldn't start a session. Request a new code and try again."
            case .missingSupabaseConfig:
                "Configure Supabase in Apps/Tab/Config/Secrets.xcconfig before using real authentication."
            }
        }
    }

    private(set) var phase: Phase = .loading
    private(set) var currentUser: CurrentUser?

    /// Invoked just before the phase flips to `.signedOut`, so the owner can
    /// clear local state (SwiftData) before the previous user's session ends.
    var onSignedOut: (@MainActor () async -> Void)?

    /// Invoked at the start of an explicit sign-out, while the session is still
    /// valid — server-side cleanup (push device deregistration) needs auth.
    var onWillSignOut: (@MainActor () async -> Void)?

    private let client = SupabaseClientProvider.shared
    private let pendingEmailNamePrefix = "auth.pendingEmailSignInName."

    /// Clears local user state, runs the sign-out hook, then publishes signedOut.
    private func enterSignedOut() async {
        currentUser = nil
        await onSignedOut?()
        phase = .signedOut
    }

    init() {
        #if DEBUG
        if Self.useMockAuth() {
            let id = Self.mockUserID
            currentUser = CurrentUser(
                id: id,
                email: "mock@tab.local",
                displayEmail: "mock@tab.local",
                displayName: "Test User",
                hasPrivateRelayEmail: false
            )
            phase = .signedIn(id)
            return
        }
        #endif

        guard SupabaseConfig.isConfigured else {
            currentUser = nil
            phase = .signedOut
            return
        }

        Task { [weak self] in
            await self?.observeAuthState()
        }
    }

    #if DEBUG
    static let mockUserID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

    var isUsingMockAuth: Bool {
        Self.useMockAuth()
    }

    private static func useMockAuth() -> Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["TAB_REAL_AUTH"] == "1" {
            return false
        }
        return environment["TAB_MOCK_AUTH"] == "1"
    }
    #endif

    private func observeAuthState() async {
        for await (event, session) in client.auth.authStateChanges {
            if let session {
                if event == .initialSession, session.isExpired {
                    currentUser = nil
                    phase = .loading
                    Task { [weak self] in
                        await self?.resolveExpiredInitialSession()
                    }
                    continue
                }

                await setSignedIn(from: session.user)
            } else {
                await enterSignedOut()
            }
        }
    }

    private func resolveExpiredInitialSession() async {
        do {
            let session = try await client.auth.session
            await setSignedIn(from: session.user)
        } catch {
            await enterSignedOut()
        }
    }

    func signInWithApple(idToken: String, nonce: String, fullName: String?) async throws {
        try requireSupabaseConfig()

        let session = try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )

        let displayName = Self.normalizedDisplayName(fullName)
        if let displayName {
            let updatedUser = try? await updateUserMetadata(displayName: displayName)
            currentUser = Self.currentUser(from: updatedUser ?? session.user, displayNameOverride: displayName)
        } else {
            currentUser = Self.currentUser(from: session.user)
        }
        phase = .signedIn(session.user.id)
    }

    func signInWithGoogle() async throws {
        try requireSupabaseConfig()

        let session = try await client.auth.signInWithOAuth(
            provider: .google,
            redirectTo: SupabaseConfig.authCallbackURL
        ) { webSession in
            webSession.prefersEphemeralWebBrowserSession = false
        }
        currentUser = Self.currentUser(from: session.user)
        phase = .signedIn(session.user.id)
    }

    @discardableResult
    func sendEmailCode(
        email rawEmail: String,
        fullName rawFullName: String,
        captchaToken: String? = nil
    ) async throws -> String {
        try requireSupabaseConfig()

        guard let displayName = Self.normalizedDisplayName(rawFullName) else {
            throw AuthInputError.missingName
        }
        guard let email = Self.normalizedEmail(rawEmail), Self.looksLikeEmail(email) else {
            throw AuthInputError.invalidEmail
        }

        try await client.auth.signInWithOTP(
            email: email,
            redirectTo: SupabaseConfig.authCallbackURL,
            shouldCreateUser: true,
            data: Self.displayNameMetadata(displayName),
            captchaToken: captchaToken
        )

        UserDefaults.standard.set(displayName, forKey: pendingNameKey(for: email))
        return email
    }

    func verifyEmailCode(email rawEmail: String, code rawCode: String) async throws {
        try requireSupabaseConfig()

        guard let email = Self.normalizedEmail(rawEmail), Self.looksLikeEmail(email) else {
            throw AuthInputError.invalidEmail
        }
        guard let code = Self.normalizedVerificationCode(rawCode) else {
            throw AuthInputError.invalidCode
        }

        let response = try await client.auth.verifyOTP(
            email: email,
            token: code,
            type: .email,
            redirectTo: SupabaseConfig.authCallbackURL
        )

        guard response.session != nil else {
            throw AuthInputError.missingVerifiedSession
        }

        await setSignedIn(from: response.user)
    }

    /// Applies any pending email profile name, then publishes the signed-in user and phase.
    private func setSignedIn(from user: User) async {
        let resolved = await applyingPendingEmailProfileIfNeeded(to: user)
        currentUser = Self.currentUser(from: resolved)
        phase = .signedIn(resolved.id)
    }

    func handleAuthCallback(_ url: URL) {
        guard Self.isExpectedAuthCallbackURL(url) else { return }
        client.auth.handle(url)
    }

    func signOut() async {
        await onWillSignOut?()
        try? await client.auth.signOut()
        // Mock auth has no real session, so authStateChanges never fires the
        // signedOut transition — drive it (and the local wipe) directly. For
        // real sessions this is idempotent with the observer.
        await enterSignedOut()
    }

    /// Permanently deletes the account via the delete-account edge function
    /// (server purges data + auth user), then tears down the local session.
    func deleteAccount() async throws {
        #if DEBUG
        if isUsingMockAuth {
            await enterSignedOut()
            return
        }
        #endif
        try requireSupabaseConfig()

        try await client.functions.invoke("delete-account")

        // The auth user no longer exists server-side; sign-out is local
        // cleanup and may fail harmlessly against the dead session.
        try? await client.auth.signOut()
        await enterSignedOut()
    }

    private func applyingPendingEmailProfileIfNeeded(to user: User) async -> User {
        guard
            let email = Self.normalizedEmail(user.email),
            let displayName = UserDefaults.standard.string(forKey: pendingNameKey(for: email))
        else {
            return user
        }

        do {
            let updatedUser = try await updateUserMetadata(displayName: displayName)
            UserDefaults.standard.removeObject(forKey: pendingNameKey(for: email))
            return updatedUser
        } catch {
            return user
        }
    }

    private func updateUserMetadata(displayName: String) async throws -> User {
        try await client.auth.update(
            user: UserAttributes(data: Self.displayNameMetadata(displayName))
        )
    }

    private func requireSupabaseConfig() throws {
        guard SupabaseConfig.isConfigured else {
            throw AuthInputError.missingSupabaseConfig
        }
    }

    private nonisolated static func displayNameMetadata(_ displayName: String) -> [String: AnyJSON] {
        [
            "display_name": .string(displayName),
            "full_name": .string(displayName),
            "name": .string(displayName),
        ]
    }

    private func pendingNameKey(for email: String) -> String {
        pendingEmailNamePrefix + email
    }

    nonisolated static func currentUser(from user: User, displayNameOverride: String? = nil) -> CurrentUser {
        let normalizedEmail = normalizedEmail(user.email)
        let isPrivateRelay = normalizedEmail?.hasSuffix("@privaterelay.appleid.com") ?? false
        let displayName = normalizedDisplayName(displayNameOverride) ?? displayName(from: user)
        return CurrentUser(
            id: user.id,
            email: user.email,
            displayEmail: isPrivateRelay ? nil : normalizedEmail,
            displayName: displayName,
            hasPrivateRelayEmail: isPrivateRelay
        )
    }

    nonisolated static func displayName(from user: User) -> String {
        if let displayName = normalizedDisplayName(user.userMetadata["display_name"]?.stringValue) {
            return displayName
        }
        if let givenName = normalizedDisplayName(user.userMetadata["given_name"]?.stringValue) {
            return givenName
        }
        if let fullName = normalizedDisplayName(user.userMetadata["full_name"]?.stringValue) {
            return fullName
        }
        if let name = normalizedDisplayName(user.userMetadata["name"]?.stringValue) {
            return name
        }
        return fallbackDisplayName(fromEmail: user.email)
    }

    nonisolated static func fallbackDisplayName(fromEmail email: String?) -> String {
        guard let email, !isApplePrivateRelayEmail(email) else { return "You" }
        let prefix = email.split(separator: "@").first.map(String.init) ?? "You"
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "You" : String(trimmed.prefix(60)).capitalized
    }

    nonisolated static func visibleEmail(from email: String?) -> String? {
        guard let email = normalizedEmail(email), !isApplePrivateRelayEmail(email) else { return nil }
        return email
    }

    nonisolated static func isApplePrivateRelayEmail(_ email: String?) -> Bool {
        guard let email = normalizedEmail(email) else { return false }
        return email.hasSuffix("@privaterelay.appleid.com")
    }

    nonisolated static func normalizedEmail(_ email: String?) -> String? {
        guard let email else { return nil }
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func normalizedVerificationCode(_ code: String?) -> String? {
        guard let code else { return nil }
        let digits = code.filter(\.isNumber)
        guard digits.count == Self.emailVerificationCodeLength else { return nil }
        return String(digits)
    }

    nonisolated static func isExpectedAuthCallbackURL(_ url: URL) -> Bool {
        guard url.scheme == SupabaseConfig.authCallbackScheme else { return false }
        guard url.host == SupabaseConfig.authCallbackURL.host else { return false }
        return url.path.isEmpty || url.path == "/"
    }

    private nonisolated static func looksLikeEmail(_ email: String) -> Bool {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, let domain = parts.last else { return false }
        return domain.contains(".") && !email.contains(" ")
    }

    nonisolated static func normalizedDisplayName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(60))
    }
}

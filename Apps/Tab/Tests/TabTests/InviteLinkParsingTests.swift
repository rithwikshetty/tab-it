import Foundation
import Testing
@testable import Tab

@Suite("Invite link parsing")
struct InviteLinkParsingTests {
    private let token = "0123456789abcdef0123456789abcdef"

    @Test("accepts canonical and www links")
    func acceptsWebLinks() throws {
        let canonical = try #require(URL(string: "https://tab-it.app/join/\(token)"))
        let www = try #require(URL(string: "https://www.tab-it.app/join/\(token)"))

        #expect(InviteLinkService.token(from: canonical) == token)
        #expect(InviteLinkService.token(from: www) == token)
    }

    @Test("accepts the configured custom scheme")
    func acceptsCustomScheme() throws {
        let url = try #require(URL(string: "\(SupabaseConfig.authCallbackScheme)://join/\(token)"))

        #expect(InviteLinkService.token(from: url) == token)
    }

    @Test("normalizes uppercase tokens")
    func normalizesUppercaseToken() throws {
        let url = try #require(URL(string: "https://tab-it.app/join/\(token.uppercased())"))

        #expect(InviteLinkService.token(from: url) == token)
    }

    @Test("rejects other hosts and paths")
    func rejectsOtherLocations() throws {
        let wrongHost = try #require(URL(string: "https://example.com/join/\(token)"))
        let wrongPath = try #require(URL(string: "https://tab-it.app/invite/\(token)"))

        #expect(InviteLinkService.token(from: wrongHost) == nil)
        #expect(InviteLinkService.token(from: wrongPath) == nil)
    }

    @Test("rejects malformed tokens")
    func rejectsMalformedTokens() throws {
        let short = try #require(URL(string: "https://tab-it.app/join/\(String(token.dropLast()))"))
        let long = try #require(URL(string: "https://tab-it.app/join/\(token)0"))
        let nonHex = try #require(URL(string: "https://tab-it.app/join/0123456789abcdef0123456789abcdeg"))

        #expect(InviteLinkService.token(from: short) == nil)
        #expect(InviteLinkService.token(from: long) == nil)
        #expect(InviteLinkService.token(from: nonHex) == nil)
    }

    @Test("does not treat auth callbacks as invites")
    func rejectsAuthCallback() throws {
        let url = try #require(URL(string: "\(SupabaseConfig.authCallbackScheme)://auth-callback?code=abc"))

        #expect(InviteLinkService.token(from: url) == nil)
    }
}

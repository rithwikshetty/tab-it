import Testing
@testable import Tab

@Suite("Invite join error messages")
struct InviteJoinErrorMessageTests {
    @Test("missing verified email explains how to join")
    func missingVerifiedEmailExplainsHowToJoin() {
        #expect(
            InviteJoinErrorMessage.message(forPostgresCode: "22023")
                == "Your account doesn't have a verified email. Verify your email, then open the invite link again."
        )
    }

    @Test("invalid or disabled invite errors keep their message")
    func invalidOrDisabledInviteErrorsKeepTheirMessage() {
        let message = "This invite link is invalid or was turned off."

        #expect(InviteJoinErrorMessage.message(forPostgresCode: "P0002") == message)
        #expect(InviteJoinErrorMessage.message(forPostgresCode: "42501") == message)
    }

    @Test("missing Postgres code has no mapped message")
    func missingPostgresCodeHasNoMappedMessage() {
        #expect(InviteJoinErrorMessage.message(forPostgresCode: nil) == nil)
    }

    @Test("unrelated Postgres code has no mapped message")
    func unrelatedPostgresCodeHasNoMappedMessage() {
        #expect(InviteJoinErrorMessage.message(forPostgresCode: "23505") == nil)
    }
}

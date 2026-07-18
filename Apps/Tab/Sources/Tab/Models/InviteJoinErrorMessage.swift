enum InviteJoinErrorMessage {
    static func message(forPostgresCode code: String?) -> String? {
        guard let code else { return nil }

        return switch code {
        case "22023":
            "Your account doesn't have a verified email. Verify your email, then open the invite link again."
        case "P0002", "42501":
            "This invite link is invalid or was turned off."
        default:
            nil
        }
    }
}

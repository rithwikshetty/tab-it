import Foundation

// MARK: - Profile

struct ProfileDTO: Codable, Sendable {
    let id: UUID
    let displayName: String
    let avatarURL: String?
    let activityLastSeenAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case activityLastSeenAt = "activity_last_seen_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

// MARK: - Trip

struct TripDTO: Codable, Sendable {
    let id: UUID
    let name: String
    let kind: String
    let memberSignature: String?
    let createdBy: UUID
    let lastActivityAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id, name, kind
        case memberSignature = "member_signature"
        case createdBy = "created_by"
        case lastActivityAt = "last_activity_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case writeID = "write_id"
    }
}

struct TripUpdateDTO: Codable, Sendable {
    let name: String?
    let deletedAt: Date?
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case name
        case deletedAt = "deleted_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

// MARK: - TripPerson

struct TripPersonDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let userID: UUID?
    let email: String
    let displayName: String
    let invitedBy: UUID?
    let joinedAt: Date?
    let removedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case userID = "user_id"
        case email
        case displayName = "display_name"
        case invitedBy = "invited_by"
        case joinedAt = "joined_at"
        case removedAt = "removed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

struct TripPersonSuggestionDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String { email }
    let userID: UUID?
    let email: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case email
        case displayName = "display_name"
    }
}

// MARK: - Category

struct CategoryDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID?
    let name: String
    let icon: String
    let isDefault: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case name, icon
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case writeID = "write_id"
    }
}

// MARK: - Expense

struct ExpenseDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let amount: Decimal
    let currency: String
    let categoryID: UUID?
    let description: String
    let expenseDate: Date
    let receiptStoragePath: String?
    let paymentMethod: String
    let createdBy: UUID
    let lastEditedBy: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case amount, currency
        case categoryID = "category_id"
        case description
        case expenseDate = "expense_date"
        case receiptStoragePath = "receipt_storage_path"
        case paymentMethod = "payment_method"
        case createdBy = "created_by"
        case lastEditedBy = "last_edited_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case writeID = "write_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        tripID = try c.decode(UUID.self, forKey: .tripID)
        amount = try c.decode(Decimal.self, forKey: .amount)
        currency = try c.decode(String.self, forKey: .currency)
        categoryID = try c.decodeIfPresent(UUID.self, forKey: .categoryID)
        description = try c.decode(String.self, forKey: .description)
        // `expense_date` is a Postgres `date` (bare `yyyy-MM-dd`, no time component).
        // The Supabase client's default date strategy only parses full ISO-8601
        // timestamps, so it throws on a date-only string — which would abort the
        // entire pull (expenses, payments, splits, settlements) after trips have
        // already synced. Decode it as a plain string and parse it ourselves; the
        // remaining timestamptz fields stay on the client's default strategy.
        let rawExpenseDate = try c.decode(String.self, forKey: .expenseDate)
        expenseDate = try Self.parseExpenseDate(rawExpenseDate, container: c)
        receiptStoragePath = try c.decodeIfPresent(String.self, forKey: .receiptStoragePath)
        paymentMethod = try c.decode(String.self, forKey: .paymentMethod)
        createdBy = try c.decode(UUID.self, forKey: .createdBy)
        lastEditedBy = try c.decodeIfPresent(UUID.self, forKey: .lastEditedBy)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        writeID = try c.decode(UUID.self, forKey: .writeID)
    }

    private static func parseExpenseDate(
        _ raw: String,
        container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date {
        if let date = parseDateOnlyAtUTCNoon(raw) { return date }
        // Defensive fallback: tolerate a full ISO-8601 timestamp if the column shape ever changes.
        if let date = try? Date(raw, strategy: .iso8601) { return date }
        throw DecodingError.dataCorruptedError(
            forKey: .expenseDate,
            in: container,
            debugDescription: "Unrecognized expense_date format: \(raw)"
        )
    }

    /// Date-only values are represented at UTC noon so local date formatters do
    /// not render the previous day for users west of UTC.
    private static func parseDateOnlyAtUTCNoon(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: raw)?.addingTimeInterval(12 * 60 * 60)
    }
}

struct ExpenseDeleteUpdateDTO: Codable, Sendable {
    let deletedAt: Date?
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

// MARK: - ExpensePayment

struct ExpensePaymentDTO: Codable, Sendable {
    let expenseID: UUID
    let tripPersonID: UUID
    let amountPaid: Decimal
    let paymentMode: String
    let createdAt: Date
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case expenseID = "expense_id"
        case tripPersonID = "trip_person_id"
        case amountPaid = "amount_paid"
        case paymentMode = "payment_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

// MARK: - ExpenseSplit

struct ExpenseSplitDTO: Codable, Sendable {
    let expenseID: UUID
    let tripPersonID: UUID
    let amountOwed: Decimal
    let splitType: String
    let shareUnits: Decimal?
    let percentage: Decimal?
    let createdAt: Date
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case expenseID = "expense_id"
        case tripPersonID = "trip_person_id"
        case amountOwed = "amount_owed"
        case splitType = "split_type"
        case shareUnits = "share_units"
        case percentage
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

// MARK: - Settlement

struct SettlementDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let fromPersonID: UUID
    let toPersonID: UUID
    let amount: Decimal
    let currency: String
    let note: String?
    let settledAt: Date
    let createdBy: UUID
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case fromPersonID = "from_person_id"
        case toPersonID = "to_person_id"
        case amount, currency, note
        case settledAt = "settled_at"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case writeID = "write_id"
    }
}

struct SettlementInsertDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let fromPersonID: UUID
    let toPersonID: UUID
    let amount: Decimal
    let currency: String
    let note: String?
    let settledAt: Date
    let createdBy: UUID
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case fromPersonID = "from_person_id"
        case toPersonID = "to_person_id"
        case amount, currency, note
        case settledAt = "settled_at"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

struct SettlementDeleteUpdateDTO: Codable, Sendable {
    let deletedAt: Date?
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

// MARK: - Activity

struct ActivityDTO: Codable, Sendable {
    let id: UUID
    let tripID: UUID
    let actorID: UUID
    let action: String
    let entityType: String
    let entityID: UUID
    let timestamp: Date
    let snapshot: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case tripID = "trip_id"
        case actorID = "actor_id"
        case action
        case entityType = "entity_type"
        case entityID = "entity_id"
        case timestamp
        case snapshot = "snapshot_json"
    }
}

// MARK: - Trip mute preference

struct TripMuteDTO: Codable, Sendable {
    let tripID: UUID
    let userID: UUID
    let mutedAt: Date
    let updatedAt: Date
    let writeID: UUID

    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id"
        case userID = "user_id"
        case mutedAt = "muted_at"
        case updatedAt = "updated_at"
        case writeID = "write_id"
    }
}

struct TripMuteInsertDTO: Codable, Sendable {
    let tripID: UUID
    let userID: UUID

    enum CodingKeys: String, CodingKey {
        case tripID = "trip_id"
        case userID = "user_id"
    }
}

// MARK: - Push device

struct PushDeviceInsertDTO: Codable, Sendable {
    let userID: UUID
    let apnsToken: String
    let deviceName: String?

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case apnsToken = "apns_token"
        case deviceName = "device_name"
    }
}

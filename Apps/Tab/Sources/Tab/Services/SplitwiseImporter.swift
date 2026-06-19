import Foundation
import SwiftData
import TabCore

/// Writes a parsed Splitwise export into a real trip.
///
/// The "self" column maps to the current account (the trip creator); every other
/// Splitwise name becomes its own trip person. Under a real session those people
/// are created through `add_trip_person_by_email` so they sync; under mock auth
/// (no session) they're inserted locally, mirroring `NewTripSheet`'s debug path.
/// Reconstructed expenses/settlements are balance-identical to the source export
/// (verified in `TabCore`'s `SplitwiseImportTests`). If any step fails, the
/// partially-created trip is soft-deleted so a retry starts clean.
@MainActor
struct SplitwiseImporter {
    let context: ModelContext
    let sync: SyncService
    let auth: AuthService

    enum ImportError: LocalizedError {
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "You need to be signed in to import."
            }
        }
    }

    func run(_ parsed: SplitwiseImport.Result, tripName: String, selfPerson: String?) async throws {
        guard let user = auth.currentUser else { throw ImportError.notSignedIn }

        let trip = TripEntity(name: tripName, createdByID: user.id)
        let creator = TripPersonEntity(
            userID: user.id,
            email: user.email.map(Self.normalizedEmail) ?? "\(user.id.uuidString.lowercased())@users.tab",
            displayName: user.displayName,
            invitedByID: user.id,
            trip: trip,
            joinedAt: .now
        )

        do {
            context.insert(trip)
            context.insert(creator)
            try context.save()
            try await write(parsed, tripName: tripName, selfPerson: selfPerson, trip: trip, creator: creator, user: user)
        } catch {
            // Roll back the partial import so the user doesn't see a half-built
            // trip and a retry doesn't create a duplicate. The tombstone syncs.
            Deletion.softDelete(trip: trip, in: context)
            await sync.pushPending()
            throw error
        }

        await sync.pushPending()
    }

    private func write(
        _ parsed: SplitwiseImport.Result,
        tripName: String,
        selfPerson: String?,
        trip: TripEntity,
        creator: TripPersonEntity,
        user: CurrentUser
    ) async throws {
        // Map every Splitwise name to a trip-person id.
        var personIDs: [String: UUID] = [:]
        if let selfPerson { personIDs[selfPerson] = creator.id }
        for name in parsed.people where personIDs[name] == nil {
            personIDs[name] = try await makePerson(named: name, in: trip, invitedBy: user.id)
        }

        for row in parsed.expenses {
            let expense = ExpenseEntity(
                amount: row.total,
                currency: row.currency,
                categoryID: Self.categoryID(for: row.category),
                descriptionText: row.description,
                expenseDate: row.date,
                paymentMethodRaw: PaymentMethod.card.rawValue,
                createdByID: user.id,
                trip: trip
            )
            context.insert(expense)

            let singleFullPayer = row.payments.count == 1 && row.payments[0].amount == row.total
            for share in row.payments {
                guard let payerID = personIDs[share.person] else { continue }
                context.insert(PaymentEntity(
                    tripPersonID: payerID,
                    amountPaid: share.amount,
                    paymentModeRaw: (singleFullPayer ? SplitType.equal : SplitType.exact).rawValue,
                    expense: expense
                ))
            }
            for share in row.splits {
                guard let participantID = personIDs[share.person] else { continue }
                context.insert(ExpenseSplitEntity(
                    tripPersonID: participantID,
                    amountOwed: share.amount,
                    splitTypeRaw: SplitType.exact.rawValue,
                    expense: expense
                ))
            }
        }

        for row in parsed.settlements {
            guard let from = personIDs[row.from], let to = personIDs[row.to] else { continue }
            context.insert(SettlementEntity(
                fromPersonID: from,
                toPersonID: to,
                amount: row.amount,
                currency: row.currency,
                note: nil,
                settledAt: row.date,
                createdByID: user.id,
                trip: trip
            ))
        }

        trip.lastActivityAt = .now
        try context.save()
    }

    /// Creates a non-self person, returning its trip-person id.
    private func makePerson(named name: String, in trip: TripEntity, invitedBy: UUID) async throws -> UUID {
        let id = UUID()
        let email = "\(id.uuidString.lowercased())@users.tab"
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Under mock auth there is no real session, so these never sync — insert
        // locally, the same as NewTripSheet's debug fixtures. `isUsingMockAuth`
        // only exists in DEBUG builds, so this branch is compiled out of Release.
        var insertLocally = false
        #if DEBUG
        insertLocally = auth.isUsingMockAuth
        #endif
        if insertLocally {
            context.insert(TripPersonEntity(
                id: id,
                email: email,
                displayName: displayName,
                invitedByID: invitedBy,
                trip: trip,
                joinedAt: nil
            ))
            try context.save()
            return id
        }

        return try await sync.addTripPerson(
            tripID: trip.id,
            email: email,
            displayName: displayName,
            personID: id
        )
    }

    // MARK: - Category mapping

    /// Maps a Splitwise category leaf name onto one of tab's default categories,
    /// defaulting to "Other".
    static func categoryID(for splitwiseCategory: String) -> UUID {
        switch splitwiseCategory.lowercased().trimmingCharacters(in: .whitespaces) {
        case "food and drink", "dining out", "dining", "groceries", "liquor", "restaurant", "drinks":
            return DefaultCategories.food.id
        case "transportation", "taxi", "car", "gas/fuel", "fuel", "gas", "bus/train",
             "bus", "train", "plane", "parking", "bicycle", "transport":
            return DefaultCategories.transport.id
        case "hotel", "rent", "mortgage", "accommodation", "lodging", "hostel", "airbnb":
            return DefaultCategories.lodging.id
        case "entertainment", "games", "movies", "music", "sports", "activities":
            return DefaultCategories.activities.id
        case "shopping", "clothing", "electronics", "furniture", "household supplies", "gifts":
            return DefaultCategories.shopping.id
        default:
            return DefaultCategories.other.id
        }
    }

    private static func normalizedEmail(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

#if DEBUG
import Foundation
import SwiftData
import UIKit

enum LegacyFixtureSeed {
    @MainActor static func seed(in context: ModelContext, userID: UUID?) {
        guard let userID else { return }
        let trips = (try? context.fetch(FetchDescriptor<TripEntity>())) ?? []
        let expenses = (try? context.fetch(FetchDescriptor<ExpenseEntity>())) ?? []
        for trip in trips { trip.pushedWriteID = nil }
        for person in (try? context.fetch(FetchDescriptor<TripPersonEntity>())) ?? [] { person.pushedWriteID = nil }
        for expense in expenses { expense.pushedWriteID = nil }
        if let trip = trips.first {
            context.insert(TripMuteEntity(tripID: trip.id, isMuted: false))
        }
        if let profile = (try? context.fetch(FetchDescriptor<ProfileEntity>()))?.first {
            profile.activityLastSeenAt = Date(timeIntervalSince1970: 1700000000)
            profile.displayName = "Offline Test User"
        }
        let activities = (try? context.fetch(FetchDescriptor<ActivityEntity>())) ?? []
        activities.first?.readAt = Date(timeIntervalSince1970: 1700000001)
        activities.dropFirst().first?.dismissedAt = Date(timeIntervalSince1970: 1700000002)
        if let expense = expenses.first, let trip = expense.trip {
            let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).image { c in
                UIColor.white.setFill()
                c.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            }.jpegData(compressionQuality: 0.9)!
            expense.receiptStoragePath = try? ReceiptStorage.persistPendingUpload(jpeg: jpeg, tripID: trip.id, expenseID: expense.id)
        }
        UserDefaults.standard.set(Date(timeIntervalSince1970: 1700000003), forKey: SyncService.pendingActivitySeenKey(for: userID))
        try? context.save()
    }
}
#endif

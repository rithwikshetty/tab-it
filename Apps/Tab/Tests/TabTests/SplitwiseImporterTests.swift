import Foundation
import Testing
@testable import Tab

@MainActor
@Suite("Splitwise importer mapping")
struct SplitwiseImporterTests {

    @Test("Splitwise categories map onto tab defaults")
    func categoryMapping() {
        #expect(SplitwiseImporter.categoryID(for: "Taxi") == DefaultCategories.transport.id)
        #expect(SplitwiseImporter.categoryID(for: "Bus/train") == DefaultCategories.transport.id)
        #expect(SplitwiseImporter.categoryID(for: "Liquor") == DefaultCategories.food.id)
        #expect(SplitwiseImporter.categoryID(for: "Groceries") == DefaultCategories.food.id)
        #expect(SplitwiseImporter.categoryID(for: "Hotel") == DefaultCategories.lodging.id)
        #expect(SplitwiseImporter.categoryID(for: "Games") == DefaultCategories.activities.id)
        #expect(SplitwiseImporter.categoryID(for: "Electronics") == DefaultCategories.shopping.id)
    }

    @Test("Unknown and General categories fall back to Other")
    func categoryFallback() {
        #expect(SplitwiseImporter.categoryID(for: "General") == DefaultCategories.other.id)
        #expect(SplitwiseImporter.categoryID(for: "Something Splitwise Invented") == DefaultCategories.other.id)
        #expect(SplitwiseImporter.categoryID(for: "") == DefaultCategories.other.id)
    }

    @Test("Category matching ignores case and surrounding space")
    func categoryNormalization() {
        #expect(SplitwiseImporter.categoryID(for: "  taxi ") == DefaultCategories.transport.id)
    }

    @Test("Self-match finds the current user's column by name")
    func selfMatchExact() {
        let people = ["Rithwik Shetty", "Lym", "Shreya Iyer"]
        #expect(ImportFromSplitwiseSheet.bestSelfMatch(people: people, displayName: "Rithwik Shetty") == "Rithwik Shetty")
    }

    @Test("Self-match falls back to a shared name token")
    func selfMatchToken() {
        let people = ["Rithwik Shetty", "Lym", "Shreya Iyer"]
        #expect(ImportFromSplitwiseSheet.bestSelfMatch(people: people, displayName: "Rithwik") == "Rithwik Shetty")
    }

    @Test("Self-match returns nil when nothing matches")
    func selfMatchNone() {
        let people = ["Lym", "Shreya Iyer"]
        #expect(ImportFromSplitwiseSheet.bestSelfMatch(people: people, displayName: "Test User") == nil)
        #expect(ImportFromSplitwiseSheet.bestSelfMatch(people: people, displayName: "") == nil)
    }
}

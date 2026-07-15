import Foundation
import Testing
@testable import TabCore

@Suite("CurrencyCatalog")
struct CurrencyCatalogTests {
    @Test("default code is the hard fallback currency")
    func defaultCodeIsHardFallbackCurrency() {
        #expect(CurrencyCatalog.defaultCode == "INR")
        #expect(CurrencyCatalog.isSupported(CurrencyCatalog.defaultCode))
    }

    @Test("supported currencies include common ISO 4217 codes")
    func includesCommonISOCodes() {
        #expect(CurrencyCatalog.supported.count > 100)
        #expect(CurrencyCatalog.isSupported("EUR"))
        #expect(CurrencyCatalog.isSupported("usd"))
        #expect(CurrencyCatalog.isSupported("JPY"))
        #expect(CurrencyCatalog.isSupported("KWD"))
    }

    @Test("metadata exposes symbols, names, and fraction digits")
    func metadata() throws {
        let usd = try #require(CurrencyCatalog.metadata(for: "USD"))
        let jpy = try #require(CurrencyCatalog.metadata(for: "JPY"))
        let kwd = try #require(CurrencyCatalog.metadata(for: "KWD"))

        #expect(!usd.symbol.isEmpty)
        #expect(usd.name.localizedCaseInsensitiveContains("Dollar"))
        #expect(usd.fractionDigits == 2)
        #expect(jpy.fractionDigits == 0)
        #expect(kwd.fractionDigits == 3)
    }

    @Test("precision validation respects each currency minor unit")
    func precisionValidation() {
        #expect(CurrencyCatalog.hasValidPrecision(10, currency: "JPY"))
        #expect(!CurrencyCatalog.hasValidPrecision(Decimal(string: "10.01")!, currency: "JPY"))
        #expect(CurrencyCatalog.hasValidPrecision(Decimal(string: "1.234")!, currency: "KWD"))
        #expect(!CurrencyCatalog.hasValidPrecision(Decimal(string: "1.2345")!, currency: "KWD"))
    }

    @Test("display symbols are unique — amounts render symbol-only, so shared symbols must disambiguate")
    func displaySymbolsAreUnique() {
        // NFKC-fold so lookalikes count as collisions (fullwidth ￥ vs ¥).
        let symbols = CurrencyCatalog.supported.map {
            $0.symbol.precomposedStringWithCompatibilityMapping.uppercased()
        }
        #expect(Set(symbols).count == symbols.count)
    }

    @Test("major currencies keep their bare symbol; other dollar currencies disambiguate")
    func sharedSymbolClaiming() throws {
        #expect(try #require(CurrencyCatalog.metadata(for: "USD")).symbol == "$")
        #expect(try #require(CurrencyCatalog.metadata(for: "GBP")).symbol == "£")
        #expect(try #require(CurrencyCatalog.metadata(for: "JPY")).symbol == "¥")
        #expect(try #require(CurrencyCatalog.metadata(for: "EUR")).symbol == "€")
        #expect(try #require(CurrencyCatalog.metadata(for: "INR")).symbol == "₹")
        #expect(try #require(CurrencyCatalog.metadata(for: "THB")).symbol == "฿")

        let cad = try #require(CurrencyCatalog.metadata(for: "CAD")).symbol
        let aud = try #require(CurrencyCatalog.metadata(for: "AUD")).symbol
        #expect(cad != "$")
        #expect(aud != "$")
        #expect(cad != aud)
    }

    @Test("search matches code and localized currency name")
    func search() {
        #expect(CurrencyCatalog.search("usd").contains { $0.code == "USD" })
        #expect(CurrencyCatalog.search("yen").contains { $0.code == "JPY" })
    }
}

import Testing
@testable import Tab

@Suite struct PaginatedFetchTests {
    private enum TestError: Error {
        case pageFailed
    }

    @Test func assemblesMultiplePagesInOrder() async throws {
        let values: [Int] = try await fetchAllPages(pageSize: 2) { range in
            switch range {
            case 0...1: [10, 20]
            case 2...3: [30]
            default: []
            }
        }

        #expect(values == [10, 20, 30])
    }

    @Test func exactBoundaryFetchesFollowingEmptyPage() async throws {
        let requestedRanges = RequestedRanges()

        let values: [Int] = try await fetchAllPages(pageSize: 2) { range in
            await requestedRanges.append(range)
            return switch range {
            case 0...1: [10, 20]
            case 2...3: [30, 40]
            default: []
            }
        }

        #expect(values == [10, 20, 30, 40])
        #expect(await requestedRanges.values == [0...1, 2...3, 4...5])
    }

    @Test func emptyFirstPageReturnsEmpty() async throws {
        let values: [Int] = try await fetchAllPages(pageSize: 2) { _ in [] }

        #expect(values.isEmpty)
    }

    @Test func throwingPageFailsWholeFetch() async {
        await #expect(throws: TestError.pageFailed) {
            let _: [Int] = try await fetchAllPages(pageSize: 2) { range in
                if range.lowerBound == 2 { throw TestError.pageFailed }
                return [10, 20]
            }
        }
    }
}

private actor RequestedRanges {
    private(set) var values: [ClosedRange<Int>] = []

    func append(_ range: ClosedRange<Int>) {
        values.append(range)
    }
}

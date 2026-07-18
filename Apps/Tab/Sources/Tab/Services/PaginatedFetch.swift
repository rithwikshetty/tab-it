/// Fetches a complete ordered result set before the caller reconciles local rows.
/// A thrown page discards the partial result, preserving the pull's nil-on-failure
/// contract and preventing partial remote state from driving local deletions.
func fetchAllPages<T: Sendable>(
    pageSize: Int = 1_000,
    fetchPage: @Sendable (_ range: ClosedRange<Int>) async throws -> [T]
) async throws -> [T] {
    precondition(pageSize > 0, "pageSize must be positive")

    var rows: [T] = []
    var start = 0
    while true {
        let page = try await fetchPage(start...(start + pageSize - 1))
        rows.append(contentsOf: page)
        guard page.count == pageSize else { return rows }
        start += pageSize
    }
}

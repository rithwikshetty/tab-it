@MainActor
final class AsyncSerialGate {
    private var tail: Task<Void, Never>?

    /// Appends work to one non-cancelling FIFO chain. A caller cancelling its
    /// wait must not drop sync work that was already accepted by the service.
    func run(_ operation: @MainActor @escaping @Sendable () async -> Void) async {
        let previous = tail
        let current = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tail = current
        await current.value
    }
}

struct OperationGeneration: Sendable {
    private var current = 0

    mutating func next() -> Int {
        current &+= 1
        return current
    }

    func isCurrent(_ generation: Int) -> Bool {
        generation == current
    }
}

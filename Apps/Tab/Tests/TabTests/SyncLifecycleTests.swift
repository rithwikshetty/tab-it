import Foundation
import Testing
@testable import Tab

@MainActor
@Suite("Sync lifecycle coordination")
struct SyncLifecycleTests {
    @Test("serial gate preserves FIFO order without overlapping operations")
    func serialGatePreservesFIFOOrder() async {
        let gate = AsyncSerialGate()
        let events = EventRecorder()
        let firstStarted = AsyncLatch()
        let releaseFirst = AsyncLatch()

        let first = Task { @MainActor in
            await gate.run {
                await events.append("first:start")
                await firstStarted.open()
                await releaseFirst.wait()
                await events.append("first:end")
            }
        }

        await firstStarted.wait()

        let second = Task { @MainActor in
            await gate.run {
                await events.append("second:start")
                await events.append("second:end")
            }
        }

        await Task.yield()
        #expect(await events.snapshot() == ["first:start"])

        await releaseFirst.open()
        await first.value
        await second.value

        #expect(await events.snapshot() == [
            "first:start", "first:end", "second:start", "second:end",
        ])
    }

    @Test("new generations invalidate older asynchronous work")
    func generationInvalidatesOlderWork() {
        var generation = OperationGeneration()

        let first = generation.next()
        #expect(generation.isCurrent(first))

        let second = generation.next()
        #expect(!generation.isCurrent(first))
        #expect(generation.isCurrent(second))
    }

    @Test("pending activity cursors are isolated by user")
    func pendingActivityCursorKeysAreUserScoped() {
        let first = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let second = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

        #expect(SyncService.pendingActivitySeenKey(for: first) ==
            "sync.pendingActivitySeenAt.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        #expect(SyncService.pendingActivitySeenKey(for: first) !=
            SyncService.pendingActivitySeenKey(for: second))
    }
}

private actor EventRecorder {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

private actor AsyncLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

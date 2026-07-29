package com.rithwikshetty.tab.sync

import com.rithwikshetty.tab.data.local.OutboxEntity
import com.rithwikshetty.tab.data.local.TabDatabase
import java.time.Clock
import java.time.Duration
import java.time.Instant
import kotlin.math.min
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

public data class SyncReport(
    public val pushed: Int,
    public val pushFailures: Int,
    public val remoteRowsApplied: Int,
    public val pullCompleted: Boolean,
    public val errorMessage: String?,
)

public class SyncEngine(
    private val database: TabDatabase,
    private val remote: RemoteGateway,
    private val clock: Clock = Clock.systemUTC(),
) {
    private val mutex: Mutex = Mutex()
    private val applier: RemoteSnapshotApplier = RemoteSnapshotApplier(database)

    public suspend fun syncOnce(): SyncReport = mutex.withLock {
        checkNotNull(remote.currentUser()) { "Authentication is required before synchronization." }

        var pushed = 0
        var pushFailures = 0
        var lastError: String? = null
        val now = clock.instant()

        for (item in database.outbox().ready(now.toString(), OUTBOX_BATCH_SIZE)) {
            try {
                push(item)
                pushed += 1
            } catch (error: Exception) {
                val message = error.safeMessage()
                database.outbox().markFailed(
                    item.sequence,
                    message,
                    retryAt(now, item.attemptCount).toString(),
                )
                pushFailures += 1
                lastError = message
                break
            }
        }

        try {
            val applied = applier.apply(remote.pullSnapshot())
            SyncReport(pushed, pushFailures, applied, true, lastError)
        } catch (error: Exception) {
            SyncReport(
                pushed,
                pushFailures,
                remoteRowsApplied = 0,
                pullCompleted = false,
                errorMessage = error.safeMessage(),
            )
        }
    }

    private suspend fun push(item: OutboxEntity) {
        when (item.entityType) {
            "expense" -> {
                val expense = database.expenses().findAggregate(item.entityId)
                if (expense == null) {
                    database.outbox().acknowledge(item.sequence)
                    return
                }
                val receipt = remote.pushExpense(expense)
                if (receipt.acceptedWriteId == item.writeId) {
                    database.expenses().markClean(item.entityId, item.writeId)
                }
                database.outbox().acknowledge(item.sequence)
            }
            else -> error("Unsupported outbox entity type: ${item.entityType}")
        }
    }

    internal fun retryAt(now: Instant, previousAttempts: Int): Instant {
        val exponent = min(previousAttempts, MAX_RETRY_EXPONENT)
        val seconds = min(BASE_RETRY.seconds shl exponent, MAX_RETRY.seconds)
        return now.plusSeconds(seconds)
    }

    private companion object {
        const val OUTBOX_BATCH_SIZE: Int = 50
        const val MAX_RETRY_EXPONENT: Int = 6
        val BASE_RETRY: Duration = Duration.ofSeconds(5)
        val MAX_RETRY: Duration = Duration.ofMinutes(5)
    }
}

private fun Exception.safeMessage(): String =
    (message ?: this::class.simpleName ?: "Synchronization failed")
        .replace(Regex("(?i)(apikey|authorization|token|secret)\\s*[:=]\\s*\\S+"), "$1=<redacted>")
        .take(240)

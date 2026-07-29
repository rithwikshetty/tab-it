package com.rithwikshetty.tab.domain

import java.time.Instant
import java.util.UUID

public data class Versioned<T>(
    public val value: T,
    public val updatedAt: Instant,
    public val deletedAt: Instant?,
    public val writeId: UUID,
)

public enum class MergeDecision {
    KEEP_LOCAL,
    APPLY_REMOTE,
}

public object ConflictResolver {
    public fun <T> resolve(first: Versioned<T>, second: Versioned<T>): Versioned<T> {
        val firstDeleted = first.deletedAt
        val secondDeleted = second.deletedAt
        return when {
            firstDeleted != null && secondDeleted != null -> when {
                firstDeleted > secondDeleted -> first
                secondDeleted > firstDeleted -> second
                else -> byWriteId(first, second)
            }
            firstDeleted != null -> first
            secondDeleted != null -> second
            first.updatedAt > second.updatedAt -> first
            second.updatedAt > first.updatedAt -> second
            else -> byWriteId(first, second)
        }
    }

    public fun merge(
        local: Versioned<Unit>,
        localIsDirty: Boolean,
        remote: Versioned<Unit>,
    ): MergeDecision {
        if (local.writeId == remote.writeId) return MergeDecision.KEEP_LOCAL
        if (!localIsDirty) return MergeDecision.APPLY_REMOTE
        return if (resolve(local, remote).writeId == remote.writeId) {
            MergeDecision.APPLY_REMOTE
        } else {
            MergeDecision.KEEP_LOCAL
        }
    }

    private fun <T> byWriteId(first: Versioned<T>, second: Versioned<T>): Versioned<T> =
        if (first.writeId.toString() >= second.writeId.toString()) first else second
}

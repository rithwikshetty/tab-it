package com.rithwikshetty.tab.domain

import java.math.BigDecimal
import java.time.Duration
import java.time.Instant

public enum class TripState {
    ACTIVE,
    COMPLETED,
}

public object TripStateDeriver {
    public val DEFAULT_INACTIVITY_THRESHOLD: Duration = Duration.ofDays(30)

    public fun derive(
        balances: List<UserBalance>,
        lastActivityAt: Instant,
        now: Instant,
        inactivityThreshold: Duration = DEFAULT_INACTIVITY_THRESHOLD,
    ): TripState {
        if (balances.any { it.amount.compareTo(BigDecimal.ZERO) != 0 }) return TripState.ACTIVE
        return if (Duration.between(lastActivityAt, now) >= inactivityThreshold) {
            TripState.COMPLETED
        } else {
            TripState.ACTIVE
        }
    }
}

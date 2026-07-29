package com.rithwikshetty.tab.sync

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.launch

public class RealtimeSyncCoordinator(
    private val remote: RemoteGateway,
    private val syncEngine: SyncEngine,
) {
    @OptIn(FlowPreview::class)
    public fun start(scope: CoroutineScope, tripId: String): Job = scope.launch {
        remote.observeCurrentTripChanges(tripId)
            .debounce(250)
            .collect {
                syncEngine.syncOnce()
            }
    }
}

package com.rithwikshetty.tab

import android.content.Context
import com.rithwikshetty.tab.data.LocalExpenseRepository
import com.rithwikshetty.tab.data.LocalBalanceRepository
import com.rithwikshetty.tab.data.LocalActivityRepository
import com.rithwikshetty.tab.data.LocalSettlementRepository
import com.rithwikshetty.tab.data.LocalTripRepository
import com.rithwikshetty.tab.data.local.TabDatabase
import com.rithwikshetty.tab.sync.LocalBackendConfiguration
import com.rithwikshetty.tab.sync.RemoteGateway
import com.rithwikshetty.tab.sync.SupabaseRemoteGateway
import com.rithwikshetty.tab.sync.SyncEngine

class TabContainer(context: Context) {
    val database: TabDatabase = TabDatabase.create(context)
    val tripRepository: LocalTripRepository = LocalTripRepository(database)
    val expenseRepository: LocalExpenseRepository = LocalExpenseRepository(database)
    val settlementRepository: LocalSettlementRepository = LocalSettlementRepository(database)
    val balanceRepository: LocalBalanceRepository = LocalBalanceRepository(database)
    val activityRepository: LocalActivityRepository = LocalActivityRepository(database)

    private val backendConfiguration: LocalBackendConfiguration? =
        LocalBackendConfiguration.debugOrNull()

    val remoteGateway: RemoteGateway? =
        backendConfiguration?.let(SupabaseRemoteGateway::create)

    val syncEngine: SyncEngine? =
        remoteGateway?.let { SyncEngine(database, it) }

    val isBackendConfigured: Boolean
        get() = remoteGateway != null
}

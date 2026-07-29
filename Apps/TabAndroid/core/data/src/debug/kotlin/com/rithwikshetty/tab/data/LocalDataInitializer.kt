package com.rithwikshetty.tab.data

import com.rithwikshetty.tab.data.local.TabDatabase

public object LocalDataInitializer {
    public suspend fun initialize(database: TabDatabase) {
        DebugSeedData.seedIfEmpty(database)
    }
}

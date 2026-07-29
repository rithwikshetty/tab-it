package com.rithwikshetty.tab.data

import com.rithwikshetty.tab.data.local.TabDatabase

public object LocalDataInitializer {
    public suspend fun initialize(database: TabDatabase) {
        // Release starts empty and is populated only by an authenticated sync.
    }
}

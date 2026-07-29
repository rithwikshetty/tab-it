package com.rithwikshetty.tab

import android.app.Application
import com.rithwikshetty.tab.data.LocalDataInitializer
import com.rithwikshetty.tab.data.local.TabDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class TabApplication : Application() {
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val container: TabContainer by lazy { TabContainer(this) }

    val database: TabDatabase
        get() = container.database

    override fun onCreate() {
        super.onCreate()
        applicationScope.launch {
            if (!container.isBackendConfigured) {
                LocalDataInitializer.initialize(database)
            }
        }
    }
}

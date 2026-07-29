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

    val database: TabDatabase by lazy {
        TabDatabase.create(this)
    }

    override fun onCreate() {
        super.onCreate()
        applicationScope.launch {
            LocalDataInitializer.initialize(database)
        }
    }
}

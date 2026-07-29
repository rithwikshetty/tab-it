package com.rithwikshetty.tab.data

import androidx.room.testing.MigrationTestHelper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rithwikshetty.tab.data.local.TabDatabase
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RoomSchemaTest {
    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        TabDatabase::class.java,
    )

    @Test
    fun exportedVersionOneSchemaCreatesEveryRequiredTable() {
        helper.createDatabase("tab-schema-v1", 1).use { database ->
            val required = listOf(
                "profiles",
                "trips",
                "trip_people",
                "categories",
                "expenses",
                "expense_payments",
                "expense_splits",
                "settlements",
                "activity_log",
                "trip_mute_preferences",
                "receipt_drafts",
                "sync_outbox",
            )
            required.forEach { table ->
                database.query(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = ?",
                    arrayOf(table),
                ).use { cursor ->
                    cursor.moveToFirst()
                    assertEquals("Missing Room table $table", 1, cursor.getInt(0))
                }
            }
        }
    }
}

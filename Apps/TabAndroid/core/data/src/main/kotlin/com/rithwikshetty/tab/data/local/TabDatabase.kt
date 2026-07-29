package com.rithwikshetty.tab.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [
        ProfileEntity::class,
        TripEntity::class,
        TripPersonEntity::class,
        CategoryEntity::class,
        ExpenseEntity::class,
        ExpensePaymentEntity::class,
        ExpenseSplitEntity::class,
        SettlementEntity::class,
        ActivityEntity::class,
        TripMutePreferenceEntity::class,
        ReceiptDraftEntity::class,
        OutboxEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
public abstract class TabDatabase : RoomDatabase() {
    public abstract fun profiles(): ProfileDao
    public abstract fun trips(): TripDao
    public abstract fun expenses(): ExpenseDao
    public abstract fun settlements(): SettlementDao
    public abstract fun activity(): ActivityDao
    public abstract fun preferences(): PreferenceDao
    public abstract fun outbox(): OutboxDao

    public companion object {
        public fun create(context: Context, name: String = "tab.db"): TabDatabase =
            Room.databaseBuilder(context.applicationContext, TabDatabase::class.java, name)
                .build()
    }
}

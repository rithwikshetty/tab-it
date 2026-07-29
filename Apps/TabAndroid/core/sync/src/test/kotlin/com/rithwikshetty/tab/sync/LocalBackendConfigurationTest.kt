package com.rithwikshetty.tab.sync

import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalBackendConfigurationTest {
    @Test
    fun acceptsOnlyGuardedLocalSupabaseUrls() {
        assertTrue(LocalBackendConfiguration.isAllowedLocalUrl("http://10.0.2.2:54321"))
        assertTrue(LocalBackendConfiguration.isAllowedLocalUrl("http://127.0.0.1:54321"))
        assertTrue(LocalBackendConfiguration.isAllowedLocalUrl("http://localhost:54321/"))

        assertFalse(LocalBackendConfiguration.isAllowedLocalUrl("https://example.supabase.co"))
        assertFalse(LocalBackendConfiguration.isAllowedLocalUrl("http://10.0.2.2:54322"))
        assertFalse(LocalBackendConfiguration.isAllowedLocalUrl("http://192.168.1.4:54321"))
        assertFalse(LocalBackendConfiguration.isAllowedLocalUrl("http://user@10.0.2.2:54321"))
    }

    @Test
    fun rejectsPrivilegedOrMalformedKeys() {
        assertThrows(IllegalArgumentException::class.java) {
            LocalBackendConfiguration("http://10.0.2.2:54321", "sb_secret_forbidden")
        }
        assertThrows(IllegalArgumentException::class.java) {
            LocalBackendConfiguration("http://10.0.2.2:54321", "service_role")
        }
        assertThrows(IllegalArgumentException::class.java) {
            LocalBackendConfiguration("http://10.0.2.2:54321", "")
        }
    }
}

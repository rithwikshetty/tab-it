package com.rithwikshetty.tab

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackendConfigurationTest {
    @Test
    fun debugBackendUsesTheForwardedEmulatorLoopback() {
        assertTrue(BackendConfiguration.isAllowedLocalUrl(BackendConfiguration.baseUrl))
        assertFalse(BackendConfiguration.baseUrl.contains(".supabase.co"))
    }

    @Test
    fun hostedAndMalformedUrlsAreRejected() {
        assertFalse(BackendConfiguration.isAllowedLocalUrl("https://example.supabase.co"))
        assertFalse(BackendConfiguration.isAllowedLocalUrl("not a url"))
    }
}

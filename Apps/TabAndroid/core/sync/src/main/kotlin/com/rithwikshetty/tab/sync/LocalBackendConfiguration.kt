package com.rithwikshetty.tab.sync

import java.net.URI

public data class LocalBackendConfiguration(
    public val baseUrl: String,
    public val publishableKey: String,
) {
    init {
        require(isAllowedLocalUrl(baseUrl)) {
            "Android synchronization only accepts the guarded local Supabase endpoint."
        }
        require(publishableKey.startsWith("sb_publishable_")) {
            "Android synchronization requires a Supabase publishable key."
        }
        require(
            !publishableKey.contains("service_role", ignoreCase = true) &&
                !publishableKey.startsWith("sb_secret_"),
        ) {
            "Privileged Supabase keys are forbidden in the Android client."
        }
    }

    public companion object {
        public fun debugOrNull(): LocalBackendConfiguration? {
            if (BuildConfig.LOCAL_SUPABASE_URL.isBlank() ||
                BuildConfig.LOCAL_SUPABASE_PUBLISHABLE_KEY.isBlank()
            ) {
                return null
            }
            return LocalBackendConfiguration(
                BuildConfig.LOCAL_SUPABASE_URL,
                BuildConfig.LOCAL_SUPABASE_PUBLISHABLE_KEY,
            )
        }

        internal fun isAllowedLocalUrl(value: String): Boolean {
            val parsed = runCatching { URI(value) }.getOrNull() ?: return false
            return parsed.scheme == "http" &&
                parsed.host in setOf("10.0.2.2", "127.0.0.1", "localhost") &&
                parsed.port == 54321 &&
                (parsed.path.isNullOrBlank() || parsed.path == "/") &&
                parsed.userInfo == null
        }
    }
}

package com.rithwikshetty.tab

import java.net.URI

object BackendConfiguration {
    val environment: String = BuildConfig.BACKEND_ENVIRONMENT
    val baseUrl: String = BuildConfig.BACKEND_BASE_URL

    init {
        require(baseUrl.isEmpty() || isAllowedLocalUrl(baseUrl)) {
            "Android development must not silently connect to a hosted backend."
        }
    }

    internal fun isAllowedLocalUrl(url: String): Boolean {
        val parsed = runCatching { URI(url) }.getOrNull() ?: return false
        return parsed.scheme == "http" &&
            parsed.host in setOf("10.0.2.2", "127.0.0.1", "localhost") &&
            parsed.port == 54321
    }
}

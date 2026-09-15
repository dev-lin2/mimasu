package com.handypick.mimasu.host

import android.content.Context
import android.content.SharedPreferences
import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.serialization.json.Json
import uy.kohesive.injekt.Injekt

/**
 * Registers everything an extension resolves through Injekt.
 *
 * Order matters: this must run **before** any source class is instantiated
 * (INSTRUCTIONS.md §5.2). A source's constructor commonly calls
 * `injectLazy<NetworkHelper>()`, and an unregistered lookup throws.
 */
object ShimRegistry {

    private var initialised = false

    @Synchronized
    fun ensureInitialised(context: Context) {
        if (initialised) return

        val app = context.applicationContext
        Injekt.addSingleton(NetworkHelper::class.java, NetworkHelper(app))

        // Extensions ask for SharedPreferences without qualification, so they
        // get one shared store. Per-extension namespacing happens on the host
        // side of §5.6, keyed by source id.
        Injekt.addSingletonFactory(SharedPreferences::class.java) {
            app.getSharedPreferences("extension_prefs", Context.MODE_PRIVATE)
        }

        // `parseAs` is inlined into extension code, so it looks this up
        // directly rather than going through any shim function of ours.
        // Lenient on purpose: sources parse APIs they do not control, and a
        // field added upstream should not break playback.
        Injekt.addSingleton(
            Json::class.java,
            Json {
                ignoreUnknownKeys = true
                isLenient = true
                explicitNulls = false
                coerceInputValues = true
            },
        )

        Injekt.addSingleton(Context::class.java, app)
        Injekt.addSingletonFactory(android.app.Application::class.java) {
            app as android.app.Application
        }

        initialised = true
    }
}

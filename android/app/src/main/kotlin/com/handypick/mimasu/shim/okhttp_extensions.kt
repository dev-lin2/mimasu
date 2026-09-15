@file:Suppress("PackageDirectoryMismatch", "unused")
// Extensions reference these by their file class, not their package: the dex
// of a real extension names eu.kanade.tachiyomi.network.OkHttpExtensionsKt
// (docs/phase-0-findings.md §4). Kotlin would otherwise derive the facade name
// from this file, so it is pinned.
@file:JvmName("OkHttpExtensionsKt")

/*
 * eu.kanade.tachiyomi.network — response-consuming helpers.
 *
 * Split out of RequestsKt because the ecosystem splits them: an extension that
 * only calls GET() links against RequestsKt, and one that awaits a response
 * links against this class. Putting both in one file resolves the first and
 * breaks the second.
 */
package eu.kanade.tachiyomi.network

import kotlinx.serialization.json.Json
import okhttp3.Call
import okhttp3.Response
import uy.kohesive.injekt.injectLazy

/**
 * `execute()` rather than `enqueue()`: every call site is already off the main
 * thread (the host runs source work on an executor), and blocking there costs
 * nothing a callback would save.
 */
suspend fun Call.await(): Response = execute()

/**
 * The common case. Closing the body before throwing matters — OkHttp leaks the
 * connection otherwise, and a source that retries would exhaust the pool.
 */
suspend fun Call.awaitSuccess(): Response {
    val response = execute()
    if (!response.isSuccessful) {
        response.close()
        throw Exception("HTTP error ${response.code}")
    }
    return response
}

/** Older, lib-1.x extensions consume responses as an Observable. */
fun Call.asObservable(): rx.Observable<Response> =
    rx.Observable.fromCallable { execute() }

fun Call.asObservableSuccess(): rx.Observable<Response> =
    asObservable().map { response ->
        if (!response.isSuccessful) {
            response.close()
            throw Exception("HTTP error ${response.code}")
        }
        response
    }

/**
 * Extensions inline `parseAs` at their own compile time, so their dex carries
 * the body and resolves `Json` from Injekt directly — which is why
 * ShimRegistry has to register one. This copy is for anything that links
 * against the shim rather than inlining it.
 */
val json: Json by injectLazy()

inline fun <reified T> Response.parseAs(): T = use {
    json.decodeFromString(it.body!!.string())
}

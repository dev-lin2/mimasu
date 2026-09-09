@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * eu.kanade.tachiyomi.network — the HTTP surface handed to extensions.
 *
 * Confirmed referenced by a real extension: NetworkHelper and RequestsKt
 * (docs/phase-0-findings.md §4).
 *
 * This is where INSTRUCTIONS.md §5.7's request logging attaches: extensions
 * are given a client the host built, and the host installs an interceptor on
 * it. An extension that constructs its own OkHttpClient bypasses this, which
 * is why the UI calls the log "useful rather than complete".
 */
package eu.kanade.tachiyomi.network

import android.content.Context
import okhttp3.Headers
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import java.util.concurrent.TimeUnit

/** One request an extension made, as recorded by the host. */
data class LoggedRequest(
    val host: String,
    val method: String,
    val url: String,
    val code: Int,
    val millis: Long,
    val at: Long = System.currentTimeMillis(),
)

/**
 * Records every request that goes through the client the host provides.
 * Bounded so a chatty extension cannot grow memory without limit.
 */
object RequestLog {
    private const val maxEntries = 500
    private val entries = ArrayDeque<LoggedRequest>()

    @Synchronized
    fun record(entry: LoggedRequest) {
        entries.addLast(entry)
        while (entries.size > maxEntries) entries.removeFirst()
    }

    @Synchronized
    fun snapshot(): List<LoggedRequest> = entries.toList()

    @Synchronized
    fun hostCounts(): Map<String, Int> {
        val counts = LinkedHashMap<String, Int>()
        for (e in entries) counts[e.host] = (counts[e.host] ?: 0) + 1
        return counts
    }

    @Synchronized
    fun clear() = entries.clear()
}

private class LoggingInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        val started = System.nanoTime()
        val response = try {
            chain.proceed(request)
        } catch (t: Throwable) {
            RequestLog.record(
                LoggedRequest(
                    host = request.url.host,
                    method = request.method,
                    url = request.url.toString(),
                    code = -1,
                    millis = (System.nanoTime() - started) / 1_000_000,
                ),
            )
            throw t
        }
        RequestLog.record(
            LoggedRequest(
                host = request.url.host,
                method = request.method,
                url = request.url.toString(),
                code = response.code,
                millis = (System.nanoTime() - started) / 1_000_000,
            ),
        )
        return response
    }
}

class NetworkHelper(context: Context) {

    val cookieJar: okhttp3.CookieJar = okhttp3.CookieJar.NO_COOKIES

    val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(2, TimeUnit.MINUTES)
            .addInterceptor(LoggingInterceptor())
            .build()
    }

    /**
     * Extensions ask for this when they want to bypass the host's cache or
     * interceptors. It is still our client, so it is still logged.
     */
    val cloudflareClient: OkHttpClient get() = client

    @Suppress("unused")
    val defaultUserAgentProvider: () -> String = {
        "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"
    }
}

// --- RequestsKt: the GET/POST helpers extensions call ----------------------

private val defaultCacheControl = okhttp3.CacheControl.Builder()
    .maxAge(10, TimeUnit.MINUTES)
    .build()

fun GET(
    url: String,
    headers: Headers = Headers.headersOf(),
    cache: okhttp3.CacheControl = defaultCacheControl,
): Request = Request.Builder()
    .url(url)
    .headers(headers)
    .cacheControl(cache)
    .build()

fun POST(
    url: String,
    headers: Headers = Headers.headersOf(),
    body: RequestBody = RequestBody.create(null, ByteArray(0)),
    cache: okhttp3.CacheControl = defaultCacheControl,
): Request = Request.Builder()
    .url(url)
    .post(body)
    .headers(headers)
    .cacheControl(cache)
    .build()

/** Older extensions consume responses as an Observable. */
fun okhttp3.Call.asObservable(): rx.Observable<Response> =
    rx.Observable.fromCallable { execute() }

fun okhttp3.Call.asObservableSuccess(): rx.Observable<Response> =
    asObservable().map { response ->
        if (!response.isSuccessful) {
            response.close()
            throw Exception("HTTP error ${response.code}")
        }
        response
    }

suspend fun okhttp3.Call.await(): Response = execute()

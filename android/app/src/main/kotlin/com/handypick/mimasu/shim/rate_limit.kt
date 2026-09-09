@file:Suppress("PackageDirectoryMismatch", "unused")
// Extensions reference eu.kanade.tachiyomi.network.interceptor.RateLimitInterceptorKt
// by that exact JVM name.
@file:JvmName("RateLimitInterceptorKt")

/*
 * eu.kanade.tachiyomi.network.interceptor — rate limiting.
 *
 * Extensions call `client = network.client.newBuilder().rateLimit(3).build()`
 * in their constructor, so this is needed before a source can even be
 * instantiated. Discovered by loading a real extension and reading the
 * NoClassDefFoundError.
 *
 * A real implementation, not a no-op: a source that asked to be polite should
 * be polite, or Mimasu becomes the reason a site blocks the user.
 */
package eu.kanade.tachiyomi.network.interceptor

import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import java.util.concurrent.TimeUnit
import kotlin.time.Duration.Companion.seconds

/**
 * Permits-per-period limiter. Blocks the calling thread when the window is
 * full, which is safe because extension calls never run on the platform
 * thread (see ExtensionHostImpl).
 */
private class RateLimitInterceptor(
    private val permits: Int,
    private val periodMillis: Long,
    private val host: String?,
) : Interceptor {

    private val timestamps = ArrayDeque<Long>()

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        if (host != null && !request.url.host.equals(host, ignoreCase = true)) {
            return chain.proceed(request)
        }
        if (permits > 0) awaitPermit()
        return chain.proceed(request)
    }

    private fun awaitPermit() {
        while (true) {
            val waitFor: Long
            synchronized(timestamps) {
                val now = System.currentTimeMillis()
                while (timestamps.isNotEmpty() &&
                    now - timestamps.first() >= periodMillis
                ) {
                    timestamps.removeFirst()
                }
                if (timestamps.size < permits) {
                    timestamps.addLast(now)
                    return
                }
                waitFor = periodMillis - (now - timestamps.first())
            }
            if (waitFor > 0) {
                try {
                    Thread.sleep(waitFor)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return
                }
            }
        }
    }
}

fun OkHttpClient.Builder.rateLimit(
    permits: Int,
    period: Long = 1,
    unit: TimeUnit = TimeUnit.SECONDS,
): OkHttpClient.Builder =
    addInterceptor(RateLimitInterceptor(permits, unit.toMillis(period), null))

fun OkHttpClient.Builder.rateLimitHost(
    httpUrl: HttpUrl,
    permits: Int,
    period: Long = 1,
    unit: TimeUnit = TimeUnit.SECONDS,
): OkHttpClient.Builder = addInterceptor(
    RateLimitInterceptor(permits, unit.toMillis(period), httpUrl.host),
)

fun OkHttpClient.Builder.rateLimitHost(
    url: String,
    permits: Int,
    period: Long = 1,
    unit: TimeUnit = TimeUnit.SECONDS,
): OkHttpClient.Builder = addInterceptor(
    RateLimitInterceptor(
        permits,
        unit.toMillis(period),
        url.toHttpUrlOrNull()?.host ?: url,
    ),
)

/**
 * The current lib expresses the window as a kotlin.time.Duration, which is a
 * value class. That is why the extension looks for a name-mangled symbol:
 * `rateLimit-SxA4cEA$default(Builder, I, J, I, Object)` — the J being the
 * Duration's backing Long. Read off a real NoSuchMethodError; do not
 * "simplify" this to a plain Long.
 */
fun OkHttpClient.Builder.rateLimit(
    permits: Int,
    period: kotlin.time.Duration = 1.seconds,
): OkHttpClient.Builder = addInterceptor(
    RateLimitInterceptor(permits, period.inWholeMilliseconds, null),
)

fun OkHttpClient.Builder.rateLimitHost(
    httpUrl: HttpUrl,
    permits: Int,
    period: kotlin.time.Duration = 1.seconds,
): OkHttpClient.Builder = addInterceptor(
    RateLimitInterceptor(permits, period.inWholeMilliseconds, httpUrl.host),
)

fun OkHttpClient.Builder.rateLimitHost(
    url: String,
    permits: Int,
    period: kotlin.time.Duration = 1.seconds,
): OkHttpClient.Builder = addInterceptor(
    RateLimitInterceptor(
        permits,
        period.inWholeMilliseconds,
        url.toHttpUrlOrNull()?.host ?: url,
    ),
)

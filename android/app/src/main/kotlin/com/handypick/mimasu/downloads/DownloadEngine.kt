package com.handypick.mimasu.downloads

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import okhttp3.Headers.Companion.toHeaders
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Transfers episodes to local storage.
 *
 * The host owns download state rather than Dart, because a download outlives
 * the Flutter engine: the user can leave the app, and the foreground service
 * keeps going. Dart holds only the presentation metadata (which series, which
 * episode) and asks here for progress.
 *
 * One transfer at a time, deliberately. These are other people's servers and
 * a source that rate-limits playback will rate-limit a parallel download far
 * harder.
 */
object DownloadEngine {

    /** Mirrors the pigeon enum; converted at the boundary. */
    enum class State { QUEUED, RUNNING, COMPLETED, FAILED, CANCELLED }

    enum class Refusal { NONE, METERED, UNSUPPORTED_FORMAT }

    class Transfer(
        val id: String,
        val url: String,
        val headers: Map<String, String>,
        val fileName: String,
        val title: String,
        val subtitle: String,
    ) {
        @Volatile var state: State = State.QUEUED
        @Volatile var bytes: Long = 0
        @Volatile var total: Long = -1
        @Volatile var filePath: String? = null
        @Volatile var error: String? = null
        val cancelled = AtomicBoolean(false)
    }

    private val transfers = ConcurrentHashMap<String, Transfer>()
    private val queue = ArrayDeque<String>()
    private val worker = Executors.newSingleThreadExecutor { r ->
        Thread(r, "mimasu-downloads").apply { isDaemon = true }
    }

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            // No call timeout: an episode is large and a slow connection is
            // not an error.
            .callTimeout(0, TimeUnit.MILLISECONDS)
            .build()
    }

    private var appContext: Context? = null

    /** Told when a transfer changes, so the notification can be redrawn. */
    var onChanged: (() -> Unit)? = null

    @Synchronized
    fun initialise(context: Context) {
        if (appContext != null) return
        appContext = context.applicationContext
        restore()
    }

    // --- Public API -------------------------------------------------------

    @Synchronized
    fun enqueue(transfer: Transfer, wifiOnly: Boolean): Refusal {
        val context = appContext ?: return Refusal.UNSUPPORTED_FORMAT

        if (wifiOnly && isMetered(context)) return Refusal.METERED
        if (!isSupported(transfer.url)) return Refusal.UNSUPPORTED_FORMAT

        // Re-queueing something already here is a no-op rather than a second
        // copy of the same episode.
        if (transfers.containsKey(transfer.id)) return Refusal.NONE

        transfers[transfer.id] = transfer
        queue.addLast(transfer.id)
        persist()
        worker.execute { drain() }
        return Refusal.NONE
    }

    @Synchronized
    fun cancel(id: String) {
        val transfer = transfers[id] ?: return
        transfer.cancelled.set(true)
        if (transfer.state == State.QUEUED) {
            queue.remove(id)
            transfer.state = State.CANCELLED
        }
        persist()
        onChanged?.invoke()
    }

    @Synchronized
    fun remove(id: String) {
        val transfer = transfers.remove(id) ?: return
        transfer.cancelled.set(true)
        queue.remove(id)
        transfer.filePath?.let { runCatching { File(it).delete() } }
        persist()
        onChanged?.invoke()
    }

    fun snapshot(): List<Transfer> = transfers.values.sortedBy { it.title }

    /** Whether anything still needs the service alive. */
    fun hasWork(): Boolean = transfers.values.any {
        it.state == State.QUEUED || it.state == State.RUNNING
    }

    fun active(): Transfer? = transfers.values.firstOrNull {
        it.state == State.RUNNING
    }

    fun isMetered(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager ?: return false
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return !caps.hasCapability(
            NetworkCapabilities.NET_CAPABILITY_NOT_METERED,
        )
    }

    /**
     * Formats that can actually be written to a playable file.
     *
     * DASH is excluded on purpose: its segments need remuxing into a
     * container before anything will play them, which is a muxer's job, not
     * this one's. Saying so up front beats producing a file that fails later.
     */
    private fun isSupported(url: String): Boolean = !url.pathPart().endsWith(".mpd")

    /**
     * The path, without query or fragment.
     *
     * Both matter. A real CDN url ends
     * `..._hd_2.m3u8#cell=cf3` — the fragment alone was enough to make an
     * earlier version take a playlist for a video file and save 24KB of text
     * as a finished episode.
     */
    private fun String.pathPart(): String =
        substringBefore('?').substringBefore('#').lowercase()

    // --- The worker -------------------------------------------------------

    private fun drain() {
        while (true) {
            val id = synchronized(this) { queue.removeFirstOrNull() } ?: break
            val transfer = transfers[id] ?: continue
            if (transfer.cancelled.get()) {
                transfer.state = State.CANCELLED
                continue
            }
            run(transfer)
        }
        onChanged?.invoke()
    }

    private fun run(transfer: Transfer) {
        transfer.state = State.RUNNING
        transfer.error = null
        onChanged?.invoke()

        try {
            val hls = isHls(transfer)
            val target = outputFile(transfer, hls)
            if (hls) {
                downloadHls(transfer, target)
            } else {
                downloadDirect(transfer, target)
            }
            if (transfer.cancelled.get()) {
                transfer.state = State.CANCELLED
            } else {
                transfer.filePath = target.absolutePath
                transfer.state = State.COMPLETED
            }
        } catch (t: Throwable) {
            transfer.state = if (transfer.cancelled.get()) {
                State.CANCELLED
            } else {
                State.FAILED
            }
            transfer.error = t.message ?: t.javaClass.simpleName
        }
        persist()
        onChanged?.invoke()
    }

    /**
     * Whether this is a playlist rather than a video file.
     *
     * The url is only a hint: CDN links are frequently signed paths with no
     * extension at all. When the name does not settle it, the first kilobyte
     * does — a playlist always opens with `#EXTM3U`.
     */
    private fun isHls(transfer: Transfer): Boolean {
        val path = transfer.url.pathPart()
        if (path.endsWith(".m3u8") || path.endsWith(".m3u")) return true
        if (path.endsWith(".mp4") || path.endsWith(".mkv")) return false
        return sniffsAsPlaylist(transfer)
    }

    private fun sniffsAsPlaylist(transfer: Transfer): Boolean = runCatching {
        val request = Request.Builder()
            .url(transfer.url)
            .headers(transfer.headers.toHeaders())
            .header("Range", "bytes=0-255")
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return@runCatching false
            val head = response.body?.source()?.peek()?.readUtf8Line() ?: ""
            head.trimStart('﻿').startsWith("#EXTM3U")
        }
    }.getOrDefault(false)

    private fun outputFile(transfer: Transfer, hls: Boolean): File {
        val dir = File(appContext!!.filesDir, "downloads").apply { mkdirs() }
        // The container follows the source format: HLS segments concatenate
        // into a transport stream, everything else keeps its own extension.
        val extension = if (hls) {
            "ts"
        } else {
            transfer.url.pathPart()
                .substringAfterLast('.', "mp4")
                .filter { it.isLetterOrDigit() }
                .take(4)
                .ifEmpty { "mp4" }
        }
        return File(dir, "${transfer.id}.$extension")
    }

    private fun requestFor(url: String, headers: Map<String, String>) =
        Request.Builder().url(url).headers(headers.toHeaders()).build()

    private fun downloadDirect(transfer: Transfer, target: File) {
        client.newCall(requestFor(transfer.url, transfer.headers))
            .execute()
            .use { response ->
                if (!response.isSuccessful) {
                    throw IOException("HTTP ${response.code}")
                }
                val body = response.body ?: throw IOException("Empty response")
                transfer.total = body.contentLength()
                target.outputStream().use { out ->
                    val buffer = ByteArray(64 * 1024)
                    body.byteStream().use { input ->
                        while (true) {
                            if (transfer.cancelled.get()) return
                            val read = input.read(buffer)
                            if (read <= 0) break
                            out.write(buffer, 0, read)
                            transfer.bytes += read
                            reportOccasionally(transfer)
                        }
                    }
                }
            }
    }

    /**
     * Concatenates a media playlist's segments into one file.
     *
     * Transport-stream segments join end to end and play as-is, which is why
     * no remuxing happens here. AES-128 segments are decrypted on the way
     * through; without that the file would be written as noise and only fail
     * when the user tried to watch it.
     */
    private fun downloadHls(transfer: Transfer, target: File) {
        val playlistUrl = transfer.url.toHttpUrlOrNull()
            ?: throw IOException("Bad playlist URL")
        val playlist = fetchText(playlistUrl, transfer.headers)

        val mediaUrl = if (playlist.contains("#EXT-X-STREAM-INF")) {
            pickVariant(playlist, playlistUrl)
                ?: throw IOException("No playable variant in playlist")
        } else {
            playlistUrl
        }
        val media = if (mediaUrl == playlistUrl) {
            playlist
        } else {
            fetchText(mediaUrl, transfer.headers)
        }

        val segments = segmentUrls(media, mediaUrl)
        if (segments.isEmpty()) throw IOException("Playlist had no segments")

        val key = encryptionKey(media, mediaUrl, transfer.headers)

        target.outputStream().use { out ->
            segments.forEachIndexed { index, segment ->
                if (transfer.cancelled.get()) return
                client.newCall(requestFor(segment.toString(), transfer.headers))
                    .execute()
                    .use { response ->
                        if (!response.isSuccessful) {
                            throw IOException(
                                "HTTP ${response.code} on segment ${index + 1}",
                            )
                        }
                        val raw = response.body?.bytes()
                            ?: throw IOException("Empty segment")
                        val bytes = key?.decrypt(raw, index) ?: raw
                        out.write(bytes)
                        transfer.bytes += bytes.size
                    }
                // The server never says how large the whole thing is, so the
                // estimate comes from what the segments so far averaged.
                transfer.total =
                    transfer.bytes / (index + 1) * segments.size
                reportOccasionally(transfer)
            }
        }
    }

    private fun fetchText(url: HttpUrl, headers: Map<String, String>): String =
        client.newCall(requestFor(url.toString(), headers)).execute().use {
            if (!it.isSuccessful) throw IOException("HTTP ${it.code}")
            it.body?.string() ?: throw IOException("Empty playlist")
        }

    /** The highest-bandwidth variant a master playlist offers. */
    private fun pickVariant(playlist: String, base: HttpUrl): HttpUrl? {
        var best: Pair<Long, HttpUrl>? = null
        val lines = playlist.lines()
        lines.forEachIndexed { index, line ->
            if (!line.startsWith("#EXT-X-STREAM-INF")) return@forEachIndexed
            val bandwidth = Regex("BANDWIDTH=(\\d+)")
                .find(line)
                ?.groupValues
                ?.get(1)
                ?.toLongOrNull()
                ?: 0L
            val uri = lines.drop(index + 1)
                .firstOrNull { it.isNotBlank() && !it.startsWith("#") }
                ?: return@forEachIndexed
            val resolved = base.resolve(uri.trim()) ?: return@forEachIndexed
            if (best == null || bandwidth > best!!.first) {
                best = bandwidth to resolved
            }
        }
        return best?.second
    }

    private fun segmentUrls(media: String, base: HttpUrl): List<HttpUrl> =
        media.lines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
            .mapNotNull { base.resolve(it) }

    private class SegmentKey(
        private val key: ByteArray,
        private val iv: ByteArray?,
    ) {
        fun decrypt(data: ByteArray, index: Int): ByteArray {
            // With no IV in the playlist the media sequence number is used,
            // big-endian in the low bytes — this is what the HLS spec says.
            val vector = iv ?: ByteArray(16).also {
                it[12] = (index ushr 24 and 0xFF).toByte()
                it[13] = (index ushr 16 and 0xFF).toByte()
                it[14] = (index ushr 8 and 0xFF).toByte()
                it[15] = (index and 0xFF).toByte()
            }
            val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(key, "AES"),
                IvParameterSpec(vector),
            )
            return cipher.doFinal(data)
        }
    }

    private fun encryptionKey(
        media: String,
        base: HttpUrl,
        headers: Map<String, String>,
    ): SegmentKey? {
        val line = media.lines().firstOrNull { it.startsWith("#EXT-X-KEY") }
            ?: return null
        val method = Regex("METHOD=([A-Za-z0-9-]+)")
            .find(line)?.groupValues?.get(1) ?: "NONE"
        if (method == "NONE") return null
        if (method != "AES-128") {
            throw IOException("Unsupported stream encryption: $method")
        }
        val uri = Regex("URI=\"([^\"]+)\"")
            .find(line)?.groupValues?.get(1)
            ?: throw IOException("Encrypted stream with no key URI")
        val keyUrl = base.resolve(uri) ?: throw IOException("Bad key URI")
        val key = client.newCall(requestFor(keyUrl.toString(), headers))
            .execute()
            .use {
                if (!it.isSuccessful) throw IOException("Key HTTP ${it.code}")
                it.body?.bytes() ?: throw IOException("Empty key")
            }
        val iv = Regex("IV=0x([0-9A-Fa-f]+)")
            .find(line)?.groupValues?.get(1)
            ?.chunked(2)
            ?.map { it.toInt(16).toByte() }
            ?.toByteArray()
        return SegmentKey(key, iv)
    }

    private var lastReport = 0L

    /** Redrawing a notification on every 64KB would cost more than the copy. */
    private fun reportOccasionally(transfer: Transfer) {
        val now = System.currentTimeMillis()
        if (now - lastReport < 700) return
        lastReport = now
        onChanged?.invoke()
    }

    // --- Persistence ------------------------------------------------------
    //
    // Survives process death so a killed app does not forget what it has
    // already written to disk.

    private fun indexFile(): File =
        File(File(appContext!!.filesDir, "downloads").apply { mkdirs() },
            "index.json")

    @Synchronized
    private fun persist() {
        val context = appContext ?: return
        runCatching {
            val array = JSONArray()
            for (t in transfers.values) {
                array.put(
                    JSONObject().apply {
                        put("id", t.id)
                        put("url", t.url)
                        put("headers", JSONObject(t.headers as Map<*, *>))
                        put("fileName", t.fileName)
                        put("title", t.title)
                        put("subtitle", t.subtitle)
                        put("state", t.state.name)
                        put("bytes", t.bytes)
                        put("total", t.total)
                        put("filePath", t.filePath ?: JSONObject.NULL)
                        put("error", t.error ?: JSONObject.NULL)
                    },
                )
            }
            indexFile().writeText(array.toString())
        }.onFailure {
            // Losing the index costs the list, not the files. Never fatal.
            context.let { }
        }
    }

    private fun restore() {
        runCatching {
            val file = indexFile()
            if (!file.exists()) return
            val array = JSONArray(file.readText())
            for (i in 0 until array.length()) {
                val o = array.optJSONObject(i) ?: continue
                val headers = mutableMapOf<String, String>()
                o.optJSONObject("headers")?.let { h ->
                    for (key in h.keys()) headers[key] = h.optString(key)
                }
                val transfer = Transfer(
                    id = o.optString("id"),
                    url = o.optString("url"),
                    headers = headers,
                    fileName = o.optString("fileName"),
                    title = o.optString("title"),
                    subtitle = o.optString("subtitle"),
                )
                transfer.bytes = o.optLong("bytes")
                transfer.total = o.optLong("total", -1)
                transfer.filePath = o.optString("filePath").ifEmpty { null }
                transfer.error = o.optString("error").ifEmpty { null }
                // Anything caught mid-flight by the process dying is reported
                // as failed rather than silently resurrected: the partial file
                // is not playable and the user should decide whether to retry.
                transfer.state = when (o.optString("state")) {
                    State.COMPLETED.name -> State.COMPLETED
                    State.CANCELLED.name -> State.CANCELLED
                    State.FAILED.name -> State.FAILED
                    else -> State.FAILED
                }
                if (transfer.state == State.FAILED && transfer.error == null) {
                    transfer.error = "Interrupted"
                }
                transfers[transfer.id] = transfer
            }
        }
    }
}

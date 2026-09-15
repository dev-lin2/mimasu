package com.handypick.mimasu.host

import android.content.Context
import android.content.pm.PackageManager
import dalvik.system.PathClassLoader
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSourceFactory
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Track
import eu.kanade.tachiyomi.animesource.model.Video
import kotlinx.coroutines.runBlocking
import java.util.concurrent.Executors

/**
 * Browsing through loaded anime sources (INSTRUCTIONS.md §5, Phase 2).
 *
 * Source instances are cached. Constructing one runs extension code — often
 * building an OkHttp client with rate limiting and reading preferences — so
 * rebuilding per call would both waste work and reset the rate limiter the
 * source asked for.
 */
class SourceApiImpl(private val context: Context) : SourceApi {

    private val pm: PackageManager get() = context.packageManager

    /** Extension code never runs on the platform thread. */
    private val io = Executors.newFixedThreadPool(3)

    private val sources = HashMap<String, AnimeCatalogueSource>()
    private val loaders = HashMap<String, ClassLoader>()

    override fun clearSourceCache() {
        synchronized(sources) {
            sources.clear()
            loaders.clear()
        }
    }

    override fun browse(
        packageName: String,
        className: String,
        mode: BrowseMode,
        page: Long,
        query: String,
        callback: (Result<BrowseResult>) -> Unit,
    ) = run(callback, { e -> browseFailed(e) }) {
        val started = System.nanoTime()
        val source = source(packageName, className)
        val result = runBlocking {
            when (mode) {
                BrowseMode.POPULAR -> source.getPopularAnime(page.toInt())
                BrowseMode.LATEST -> source.getLatestUpdates(page.toInt())
                BrowseMode.SEARCH -> source.getSearchAnime(
                    page.toInt(),
                    query,
                    // The source's own defaults; a filter UI comes later.
                    safeFilters(source),
                )
            }
        }
        BrowseResult(
            ok = true,
            sourceName = safe("") { source.name },
            items = result.animes.map { it.toItem() },
            hasNextPage = result.hasNextPage,
            millis = (System.nanoTime() - started) / 1_000_000,
            error = null,
        )
    }

    override fun animeDetails(
        packageName: String,
        className: String,
        animeUrl: String,
        callback: (Result<DetailsResult>) -> Unit,
    ) = run(callback, { e -> DetailsResult(ok = false, anime = null, error = e) }) {
        val source = source(packageName, className)
        val stub = SAnime.create().apply { url = animeUrl }
        val full = runBlocking { source.getAnimeDetails(stub) }
        DetailsResult(ok = true, anime = full.toItem(), error = null)
    }

    override fun episodes(
        packageName: String,
        className: String,
        animeUrl: String,
        callback: (Result<EpisodesResult>) -> Unit,
    ) = run(callback, { e -> EpisodesResult(ok = false, items = emptyList(), error = e) }) {
        val source = source(packageName, className)
        val stub = SAnime.create().apply { url = animeUrl }
        val list = runBlocking { source.getEpisodeList(stub) }
        EpisodesResult(ok = true, items = list.map { it.toItem() }, error = null)
    }

    override fun videos(
        packageName: String,
        className: String,
        episodeUrl: String,
        callback: (Result<VideosResult>) -> Unit,
    ) = run(callback, { e -> VideosResult(ok = false, items = emptyList(), error = e) }) {
        val source = source(packageName, className)
        val stub = SEpisode.create().apply { url = episodeUrl }
        val list = runBlocking { source.getVideoList(stub) }
        VideosResult(ok = true, items = list.map { it.toItem() }, error = null)
    }

    override fun sourcePreferences(
        packageName: String,
        className: String,
        callback: (Result<List<SourcePreference>>) -> Unit,
    ) {
        io.execute {
            val result = try {
                PreferenceCollector.collect(context, source(packageName, className))
            } catch (t: Throwable) {
                // A source whose preference screen throws is still a usable
                // source; it just cannot be configured from here.
                emptyList()
            }
            callback(Result.success(result))
        }
    }

    override fun setSourcePreference(
        packageName: String,
        className: String,
        key: String,
        value: String,
        callback: (Result<Unit>) -> Unit,
    ) {
        io.execute {
            runCatching {
                val source = source(packageName, className)
                PreferenceCollector.write(
                    context,
                    source,
                    key,
                    value,
                    PreferenceCollector.collect(context, source),
                )
                // The instance read its preferences when it was constructed,
                // so it has to be rebuilt for the change to take effect.
                synchronized(sources) { sources.remove("$packageName|$className") }
            }
            callback(Result.success(Unit))
        }
    }

    // ---------------------------------------------------------------- plumbing

    /**
     * Runs [work] off the platform thread, turning any throwable into the
     * caller's own failure shape. Errors are values (§5.8): extension code is
     * fallible by nature and must never crash the app.
     */
    private fun <T> run(
        callback: (Result<T>) -> Unit,
        onError: (String) -> T,
        work: () -> T,
    ) {
        io.execute {
            val result = try {
                work()
            } catch (t: Throwable) {
                onError(t.describe())
            }
            callback(Result.success(result))
        }
    }

    private fun browseFailed(error: String) = BrowseResult(
        ok = false,
        sourceName = "",
        items = emptyList(),
        hasNextPage = false,
        millis = 0,
        error = error,
    )

    /** Cached per package+class; instantiating runs extension code. */
    private fun source(packageName: String, className: String): AnimeCatalogueSource {
        val key = "$packageName|$className"
        synchronized(sources) {
            sources[key]?.let { return it }
        }

        ShimRegistry.ensureInitialised(context)

        val apkPath = pm.getApplicationInfo(packageName, 0).sourceDir
            ?: throw IllegalStateException("no APK for $packageName")

        val loader = synchronized(sources) {
            loaders.getOrPut(packageName) {
                PathClassLoader(apkPath, javaClass.classLoader)
            }
        }

        // Metadata class names may be relative to the package.
        val qualified = if (className.startsWith(".")) {
            packageName + className
        } else {
            className
        }

        val instance = Class.forName(qualified, false, loader)
            .getDeclaredConstructor()
            .apply { isAccessible = true }
            .newInstance()

        val resolved = when (instance) {
            is AnimeSourceFactory -> instance.createSources().firstOrNull()
            else -> instance
        } ?: throw IllegalStateException("factory produced no sources")

        val catalogue = resolved as? AnimeCatalogueSource
            ?: throw IllegalStateException(
                "not an AnimeCatalogueSource: ${resolved.javaClass.name}",
            )

        synchronized(sources) { sources[key] = catalogue }
        return catalogue
    }

    /** A source may throw building its own filter list; that must not stop a search. */
    private fun safeFilters(source: AnimeCatalogueSource): AnimeFilterList =
        try {
            source.getFilterList()
        } catch (_: Throwable) {
            AnimeFilterList()
        }

    private fun <T> safe(fallback: T, block: () -> T): T =
        try { block() } catch (_: Throwable) { fallback }

    private fun SAnime.toItem() = AnimeItem(
        url = safe("") { url },
        title = safe("") { title },
        thumbnailUrl = safe(null) { thumbnail_url },
        description = safe(null) { description },
        author = safe(null) { author },
        genre = safe(null) { genre },
        status = safe(0L) { status.toLong() },
    )

    private fun SEpisode.toItem() = EpisodeItem(
        url = safe("") { url },
        name = safe("") { name },
        episodeNumber = safe(-1.0) { episode_number.toDouble() },
        dateUpload = safe(0L) { date_upload },
        scanlator = safe(null) { scanlator },
    )

    private fun Video.toItem() = VideoItem(
        url = safe("") { url },
        videoUrl = safe(null) { videoUrl },
        quality = safe("") { quality },
        headers = safe(emptyMap()) {
            headers?.let { h ->
                (0 until h.size).associate { i -> h.name(i) to h.value(i) }
            } ?: emptyMap()
        },
        subtitleTracks = safe(emptyList()) { subtitleTracks.map { it.toItem() } },
        audioTracks = safe(emptyList()) { audioTracks.map { it.toItem() } },
    )

    private fun Track.toItem() = TrackItem(url = url, label = lang)

    private fun Throwable.describe(): String {
        val cause = cause?.let { " <- ${it.javaClass.simpleName}: ${it.message}" } ?: ""
        return "${javaClass.simpleName}: ${message ?: "no message"}$cause"
    }
}

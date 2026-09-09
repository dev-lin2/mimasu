@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * eu.kanade.tachiyomi.animesource.online.AnimeHttpSource — the class an anime
 * extension extends. CONFIRMED from a real extension's classes.dex.
 *
 * The abstract members below are exactly the method names found in that dex:
 *   popularAnimeRequest / popularAnimeParse
 *   latestUpdatesRequest / latestUpdatesParse
 *   searchAnimeRequest / searchAnimeParse
 *   animeDetailsRequest / animeDetailsParse
 *   episodeListRequest / episodeListParse
 *   videoListRequest / videoListParse / videoUrlParse
 *   getAnimeUrl, getFilterList
 *
 * Signatures only; behaviour is ours (INSTRUCTIONS.md §13).
 */
package eu.kanade.tachiyomi.animesource.online

import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.network.NetworkHelper
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import uy.kohesive.injekt.injectLazy
import java.security.MessageDigest

abstract class AnimeHttpSource : AnimeCatalogueSource {

    abstract val baseUrl: String
    abstract override val lang: String
    abstract override val supportsLatest: Boolean

    protected val network: NetworkHelper by injectLazy()

    /** Extensions override this to add their own interceptors. */
    open val client: OkHttpClient get() = network.client

    open val versionId = 1

    /**
     * Derived from name, lang and versionId. Verified to reproduce the
     * ecosystem's algorithm: the ids this produces match those declared in
     * repository indexes exactly (docs/phase-0-findings.md addendum).
     */
    override val id: Long by lazy {
        val key = "${name.lowercase()}/$lang/$versionId"
        val bytes = MessageDigest.getInstance("MD5").digest(key.toByteArray())
        (0..7).map { bytes[it].toLong() and 0xff shl (8 * (7 - it)) }
            .reduce(Long::or) and Long.MAX_VALUE
    }

    open fun headersBuilder(): Headers.Builder = Headers.Builder()
        .add("User-Agent", network.defaultUserAgentProvider())

    val headers: Headers by lazy { headersBuilder().build() }

    // --- request/parse pairs the extension implements ---------------------

    abstract fun popularAnimeRequest(page: Int): Request
    abstract fun popularAnimeParse(response: Response): AnimesPage

    abstract fun latestUpdatesRequest(page: Int): Request
    abstract fun latestUpdatesParse(response: Response): AnimesPage

    abstract fun searchAnimeRequest(
        page: Int,
        query: String,
        filters: AnimeFilterList,
    ): Request
    abstract fun searchAnimeParse(response: Response): AnimesPage

    abstract fun animeDetailsParse(response: Response): SAnime
    abstract fun episodeListParse(response: Response): List<SEpisode>
    abstract fun videoListParse(response: Response): List<Video>
    abstract fun videoUrlParse(response: Response): String

    open fun animeDetailsRequest(anime: SAnime): Request =
        Request.Builder().url(baseUrl + anime.url).headers(headers).build()

    open fun episodeListRequest(anime: SAnime): Request =
        Request.Builder().url(baseUrl + anime.url).headers(headers).build()

    open fun videoListRequest(episode: SEpisode): Request =
        Request.Builder().url(baseUrl + episode.url).headers(headers).build()

    open fun getAnimeUrl(anime: SAnime): String = baseUrl + anime.url
    open fun getEpisodeUrl(episode: SEpisode): String = baseUrl + episode.url

    override fun getFilterList(): AnimeFilterList = AnimeFilterList()

    // --- orchestration, entirely ours -------------------------------------
    //
    // No extension calls these: their dex references neither Observable nor
    // Continuation, so they implement only the pairs above. Keeping this
    // blocking-inside-suspend is fine because the host always calls it off
    // the main thread.

    override suspend fun getPopularAnime(page: Int): AnimesPage =
        fetch(popularAnimeRequest(page), ::popularAnimeParse)

    override suspend fun getLatestUpdates(page: Int): AnimesPage =
        fetch(latestUpdatesRequest(page), ::latestUpdatesParse)

    override suspend fun getSearchAnime(
        page: Int,
        query: String,
        filters: AnimeFilterList,
    ): AnimesPage = fetch(searchAnimeRequest(page, query, filters), ::searchAnimeParse)

    override suspend fun getAnimeDetails(anime: SAnime): SAnime =
        fetch(animeDetailsRequest(anime), ::animeDetailsParse)

    override suspend fun getEpisodeList(anime: SAnime): List<SEpisode> =
        fetch(episodeListRequest(anime), ::episodeListParse)

    override suspend fun getVideoList(episode: SEpisode): List<Video> =
        fetch(videoListRequest(episode), ::videoListParse)

    private fun <T> fetch(request: Request, parse: (Response) -> T): T =
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                response.close()
                throw Exception("HTTP ${response.code} for ${request.url}")
            }
            parse(response)
        }
}

/** Anime sources that parse HTML with Jsoup extend this. */
abstract class ParsedAnimeHttpSource : AnimeHttpSource() {
    abstract fun popularAnimeSelector(): String
    abstract fun popularAnimeFromElement(element: org.jsoup.nodes.Element): SAnime
    abstract fun popularAnimeNextPageSelector(): String?

    abstract fun latestUpdatesSelector(): String
    abstract fun latestUpdatesFromElement(element: org.jsoup.nodes.Element): SAnime
    abstract fun latestUpdatesNextPageSelector(): String?

    abstract fun searchAnimeSelector(): String
    abstract fun searchAnimeFromElement(element: org.jsoup.nodes.Element): SAnime
    abstract fun searchAnimeNextPageSelector(): String?

    abstract fun animeDetailsParse(document: org.jsoup.nodes.Document): SAnime
    abstract fun episodeListSelector(): String
    abstract fun episodeFromElement(element: org.jsoup.nodes.Element): SEpisode
    abstract fun videoListSelector(): String
    abstract fun videoFromElement(element: org.jsoup.nodes.Element): Video
    abstract fun videoUrlParse(document: org.jsoup.nodes.Document): String

    override fun popularAnimeParse(response: Response): AnimesPage =
        parseList(response, ::popularAnimeSelector, ::popularAnimeFromElement, ::popularAnimeNextPageSelector)

    override fun latestUpdatesParse(response: Response): AnimesPage =
        parseList(response, ::latestUpdatesSelector, ::latestUpdatesFromElement, ::latestUpdatesNextPageSelector)

    override fun searchAnimeParse(response: Response): AnimesPage =
        parseList(response, ::searchAnimeSelector, ::searchAnimeFromElement, ::searchAnimeNextPageSelector)

    override fun animeDetailsParse(response: Response): SAnime =
        animeDetailsParse(response.asDocument())

    override fun episodeListParse(response: Response): List<SEpisode> =
        response.asDocument().select(episodeListSelector()).map(::episodeFromElement)

    override fun videoListParse(response: Response): List<Video> =
        response.asDocument().select(videoListSelector()).map(::videoFromElement)

    override fun videoUrlParse(response: Response): String =
        videoUrlParse(response.asDocument())

    private fun parseList(
        response: Response,
        selector: () -> String,
        from: (org.jsoup.nodes.Element) -> SAnime,
        nextPage: () -> String?,
    ): AnimesPage {
        val document = response.asDocument()
        val items = document.select(selector()).map(from)
        val hasNext = nextPage()?.let { document.select(it).isNotEmpty() } ?: false
        return AnimesPage(items, hasNext)
    }
}

private fun Response.asDocument(): org.jsoup.nodes.Document =
    org.jsoup.Jsoup.parse(body!!.string(), request.url.toString())

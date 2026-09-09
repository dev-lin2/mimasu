@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * eu.kanade.tachiyomi.source.online.HttpSource — the abstract class a source
 * extends. This is the type whose absence produced Phase 0's
 * ClassNotFoundException.
 *
 * Signatures only; behaviour is ours (INSTRUCTIONS.md §13).
 */
package eu.kanade.tachiyomi.source.online

import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import rx.Observable
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.injectLazy
import java.security.MessageDigest

abstract class HttpSource : CatalogueSource {

    abstract val baseUrl: String
    abstract override val lang: String
    abstract override val supportsLatest: Boolean

    protected val network: NetworkHelper by injectLazy()

    /**
     * Extensions frequently override this to add their own interceptors. The
     * default is the host's client, so requests are logged (§5.7).
     */
    open val client: OkHttpClient get() = network.client

    open val versionId = 1

    /**
     * Derived from name, lang and versionId, the same shape the ecosystem uses
     * so a source keeps its identity across installs. Extensions rarely
     * override it; the host reads it to key stored preferences and library
     * entries.
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

    abstract fun popularMangaRequest(page: Int): Request
    abstract fun popularMangaParse(response: Response): MangasPage

    abstract fun searchMangaRequest(
        page: Int,
        query: String,
        filters: FilterList,
    ): Request
    abstract fun searchMangaParse(response: Response): MangasPage

    abstract fun latestUpdatesRequest(page: Int): Request
    abstract fun latestUpdatesParse(response: Response): MangasPage

    abstract fun mangaDetailsParse(response: Response): SManga
    abstract fun chapterListParse(response: Response): List<SChapter>
    abstract fun pageListParse(response: Response): List<Page>
    abstract fun imageUrlParse(response: Response): String

    open fun mangaDetailsRequest(manga: SManga): Request =
        Request.Builder().url(baseUrl + manga.url).headers(headers).build()

    open fun chapterListRequest(manga: SManga): Request =
        Request.Builder().url(baseUrl + manga.url).headers(headers).build()

    open fun pageListRequest(chapter: SChapter): Request =
        Request.Builder().url(baseUrl + chapter.url).headers(headers).build()

    // --- the Observable entry points -------------------------------------

    override fun fetchPopularManga(page: Int): Observable<MangasPage> =
        fetch(popularMangaRequest(page), ::popularMangaParse)

    override fun fetchSearchManga(
        page: Int,
        query: String,
        filters: FilterList,
    ): Observable<MangasPage> =
        fetch(searchMangaRequest(page, query, filters), ::searchMangaParse)

    override fun fetchLatestUpdates(page: Int): Observable<MangasPage> =
        fetch(latestUpdatesRequest(page), ::latestUpdatesParse)

    open fun fetchMangaDetails(manga: SManga): Observable<SManga> =
        fetch(mangaDetailsRequest(manga), ::mangaDetailsParse)

    open fun fetchChapterList(manga: SManga): Observable<List<SChapter>> =
        fetch(chapterListRequest(manga), ::chapterListParse)

    open fun fetchPageList(chapter: SChapter): Observable<List<Page>> =
        fetch(pageListRequest(chapter), ::pageListParse)

    override fun getFilterList(): FilterList = FilterList()

    private fun <T> fetch(
        request: Request,
        parse: (Response) -> T,
    ): Observable<T> = Observable.fromCallable {
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                throw Exception("HTTP error ${response.code}")
            }
            parse(response)
        }
    }

    open fun getMangaUrl(manga: SManga): String = baseUrl + manga.url
    open fun getChapterUrl(chapter: SChapter): String = baseUrl + chapter.url
    open fun imageRequest(page: Page): Request =
        Request.Builder().url(page.imageUrl!!).headers(headers).build()
}

/** Sources that parse HTML with Jsoup extend this instead. */
abstract class ParsedHttpSource : HttpSource() {
    abstract fun popularMangaSelector(): String
    abstract fun popularMangaFromElement(element: org.jsoup.nodes.Element): SManga
    abstract fun popularMangaNextPageSelector(): String?

    abstract fun searchMangaSelector(): String
    abstract fun searchMangaFromElement(element: org.jsoup.nodes.Element): SManga
    abstract fun searchMangaNextPageSelector(): String?

    abstract fun latestUpdatesSelector(): String
    abstract fun latestUpdatesFromElement(element: org.jsoup.nodes.Element): SManga
    abstract fun latestUpdatesNextPageSelector(): String?

    abstract fun mangaDetailsParse(document: org.jsoup.nodes.Document): SManga
    abstract fun chapterListSelector(): String
    abstract fun chapterFromElement(element: org.jsoup.nodes.Element): SChapter
    abstract fun pageListParse(document: org.jsoup.nodes.Document): List<Page>
    abstract fun imageUrlParse(document: org.jsoup.nodes.Document): String

    override fun popularMangaParse(response: Response): MangasPage =
        parseList(response, ::popularMangaSelector, ::popularMangaFromElement, ::popularMangaNextPageSelector)

    override fun searchMangaParse(response: Response): MangasPage =
        parseList(response, ::searchMangaSelector, ::searchMangaFromElement, ::searchMangaNextPageSelector)

    override fun latestUpdatesParse(response: Response): MangasPage =
        parseList(response, ::latestUpdatesSelector, ::latestUpdatesFromElement, ::latestUpdatesNextPageSelector)

    override fun mangaDetailsParse(response: Response): SManga =
        mangaDetailsParse(response.asJsoupDocument())

    override fun chapterListParse(response: Response): List<SChapter> {
        val document = response.asJsoupDocument()
        return document.select(chapterListSelector()).map(::chapterFromElement)
    }

    override fun pageListParse(response: Response): List<Page> =
        pageListParse(response.asJsoupDocument())

    override fun imageUrlParse(response: Response): String =
        imageUrlParse(response.asJsoupDocument())

    private fun parseList(
        response: Response,
        selector: () -> String,
        from: (org.jsoup.nodes.Element) -> SManga,
        nextPage: () -> String?,
    ): MangasPage {
        val document = response.asJsoupDocument()
        val items = document.select(selector()).map(from)
        val hasNext = nextPage()?.let { document.select(it).isNotEmpty() } ?: false
        return MangasPage(items, hasNext)
    }
}

private fun Response.asJsoupDocument(): org.jsoup.nodes.Document =
    org.jsoup.Jsoup.parse(body!!.string(), request.url.toString())

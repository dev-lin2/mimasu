@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * eu.kanade.tachiyomi.source — the interfaces a source class implements, and
 * eu.kanade.tachiyomi.source.online.HttpSource, which it extends.
 *
 * Confirmed referenced by a real extension: ConfigurableSource and
 * HttpSource (docs/phase-0-findings.md §4). `HttpSource` is the superclass
 * that has to resolve before a source class can load at all — the
 * ClassNotFoundException Phase 0 hit was this missing.
 *
 * Signatures only; behaviour is ours (INSTRUCTIONS.md §13).
 */
package eu.kanade.tachiyomi.source

import androidx.preference.PreferenceScreen
import eu.kanade.tachiyomi.source.model.FilterList
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga

interface Source {
    val id: Long
    val name: String
    val lang: String get() = ""
}

interface CatalogueSource : Source {
    val supportsLatest: Boolean

    fun fetchPopularManga(page: Int): rx.Observable<MangasPage>
    fun fetchSearchManga(
        page: Int,
        query: String,
        filters: FilterList,
    ): rx.Observable<MangasPage>
    fun fetchLatestUpdates(page: Int): rx.Observable<MangasPage>

    fun getFilterList(): FilterList
}

/**
 * A source with user-facing preferences. The host supplies a PreferenceScreen
 * that *records* what the extension adds rather than rendering it, then hands
 * the descriptors to Flutter (INSTRUCTIONS.md §5.6).
 */
interface ConfigurableSource : Source {
    fun setupPreferenceScreen(screen: PreferenceScreen)
}

/** One class producing several sources, usually one per language. */
abstract class SourceFactory {
    abstract fun createSources(): List<Source>
}

interface UnmeteredSource

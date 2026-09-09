@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * eu.kanade.tachiyomi.animesource — the ANIME source interfaces.
 *
 * CONFIRMED referenced by a real anime extension: ConfigurableAnimeSource.
 * The rest mirror the manga flavour, which is confirmed.
 */
package eu.kanade.tachiyomi.animesource

import androidx.preference.PreferenceScreen
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video

interface AnimeSource {
    val id: Long
    val name: String
    val lang: String get() = ""
}

/**
 * Browsing entry points.
 *
 * Confirmed from a real lib-14 extension: extensions implement only the
 * request/parse pairs on [eu.kanade.tachiyomi.animesource.online.AnimeHttpSource]
 * — neither `rx.Observable` nor `kotlin.coroutines.Continuation` appears in
 * their dex. That means the orchestration below is entirely the host's to
 * define, and extension code never calls it.
 */
interface AnimeCatalogueSource : AnimeSource {
    val supportsLatest: Boolean

    fun getFilterList(): AnimeFilterList

    suspend fun getPopularAnime(page: Int): AnimesPage
    suspend fun getLatestUpdates(page: Int): AnimesPage
    suspend fun getSearchAnime(
        page: Int,
        query: String,
        filters: AnimeFilterList,
    ): AnimesPage
    suspend fun getAnimeDetails(anime: SAnime): SAnime
    suspend fun getEpisodeList(anime: SAnime): List<SEpisode>
    suspend fun getVideoList(episode: SEpisode): List<Video>
}

/**
 * A source with user-facing preferences. The host hands it a PreferenceScreen
 * that records what it adds rather than rendering it (§5.6).
 */
interface ConfigurableAnimeSource : AnimeSource {
    fun setupPreferenceScreen(screen: PreferenceScreen)
}

/** One class producing several sources, usually one per language. */
abstract class AnimeSourceFactory {
    abstract fun createSources(): List<AnimeSource>
}

interface UnmeteredSource

@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * eu.kanade.tachiyomi.animesource.model — the ANIME data types.
 *
 * CONFIRMED from a real anime extension's classes.dex
 * (eu.kanade.tachiyomi.animeextension.all.animeonsen, lib 14):
 *   SAnime (+Companion), SEpisode (+Companion), Video, Track,
 *   AnimesPage, AnimeFilter (+$Select), AnimeFilterList
 *
 * This is the flavour Mimasu actually needs. Signatures only, our own
 * behaviour (INSTRUCTIONS.md §13).
 */
package eu.kanade.tachiyomi.animesource.model

import okhttp3.Headers

interface SAnime {
    var url: String
    var title: String
    var artist: String?
    var author: String?
    var description: String?
    var genre: String?
    var status: Int
    var thumbnail_url: String?
    var initialized: Boolean

    fun copyFrom(other: SAnime) {
        if (other.author != null) author = other.author
        if (other.artist != null) artist = other.artist
        if (other.description != null) description = other.description
        if (other.genre != null) genre = other.genre
        if (other.thumbnail_url != null) thumbnail_url = other.thumbnail_url
        status = other.status
        if (!initialized) initialized = other.initialized
    }

    companion object {
        const val UNKNOWN = 0
        const val ONGOING = 1
        const val COMPLETED = 2
        const val LICENSED = 3
        const val PUBLISHING_FINISHED = 4
        const val CANCELLED = 5
        const val ON_HIATUS = 6

        fun create(): SAnime = SAnimeImpl()
    }
}

class SAnimeImpl : SAnime {
    override var url: String = ""
    override var title: String = ""
    override var artist: String? = null
    override var author: String? = null
    override var description: String? = null
    override var genre: String? = null
    override var status: Int = 0
    override var thumbnail_url: String? = null
    override var initialized: Boolean = false
}

interface SEpisode {
    var url: String
    var name: String
    var date_upload: Long
    var episode_number: Float
    var scanlator: String?

    fun copyFrom(other: SEpisode) {
        url = other.url
        name = other.name
        date_upload = other.date_upload
        episode_number = other.episode_number
        scanlator = other.scanlator
    }

    companion object {
        fun create(): SEpisode = SEpisodeImpl()
    }
}

class SEpisodeImpl : SEpisode {
    override var url: String = ""
    override var name: String = ""
    override var date_upload: Long = 0
    override var episode_number: Float = -1f
    override var scanlator: String? = null
}

/**
 * An external subtitle or audio track accompanying a video.
 *
 * Shape not yet verified against an extension that constructs one — this
 * extension does not. Confirm before relying on playback tracks (§8).
 */
data class Track(val url: String, val lang: String)

/**
 * One playable stream. `headers` matters: many sources 403 without a Referer,
 * and §8 requires passing them through to the player.
 *
 * Constructor shape not yet verified — see the note above.
 */
class Video(
    val url: String,
    val quality: String,
    val videoUrl: String? = null,
    val headers: Headers? = null,
    val subtitleTracks: List<Track> = emptyList(),
    val audioTracks: List<Track> = emptyList(),
) {
    // Some extensions read this back after constructing.
    var videoPageUrl: String? = url
}

class AnimesPage(val animes: List<SAnime>, val hasNextPage: Boolean)

/**
 * Filters describe a source's search UI. `Select` is subclassed by real
 * extensions, so these must stay open.
 */
sealed class AnimeFilter<T>(val name: String, var state: T) {
    abstract class Select<V>(
        name: String,
        val values: Array<V>,
        state: Int = 0,
    ) : AnimeFilter<Int>(name, state)

    abstract class Text(name: String, state: String = "") :
        AnimeFilter<String>(name, state)

    abstract class CheckBox(name: String, state: Boolean = false) :
        AnimeFilter<Boolean>(name, state)

    abstract class TriState(name: String, state: Int = STATE_IGNORE) :
        AnimeFilter<Int>(name, state) {
        fun isIgnored() = state == STATE_IGNORE
        fun isIncluded() = state == STATE_INCLUDE
        fun isExcluded() = state == STATE_EXCLUDE

        companion object {
            const val STATE_IGNORE = 0
            const val STATE_INCLUDE = 1
            const val STATE_EXCLUDE = 2
        }
    }

    abstract class Group<V>(name: String, state: List<V>) :
        AnimeFilter<List<V>>(name, state)

    abstract class Sort(
        name: String,
        val values: Array<String>,
        state: Selection? = null,
    ) : AnimeFilter<Sort.Selection?>(name, state) {
        data class Selection(val index: Int, val ascending: Boolean)
    }

    open class Header(name: String) : AnimeFilter<Any?>(name, null)
    open class Separator(name: String = "") : AnimeFilter<Any?>(name, null)
}

class AnimeFilterList(val list: List<AnimeFilter<*>>) :
    List<AnimeFilter<*>> by list {
    constructor(vararg fs: AnimeFilter<*>) : this(fs.asList())
}

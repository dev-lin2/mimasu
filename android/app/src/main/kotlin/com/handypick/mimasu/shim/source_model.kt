@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * eu.kanade.tachiyomi.source.model — the data types an extension populates.
 *
 * Confirmed referenced by a real extension (docs/phase-0-findings.md §4):
 * SManga (+Companion), SChapter (+Companion), Page, MangasPage, Filter,
 * FilterList.
 *
 * These are the MANGA flavour, used as the verification harness. The anime
 * flavour mirrors them as SAnime / SEpisode / Video / AnimesPage / AnimeFilter,
 * under eu.kanade.tachiyomi.animesource.model — still unconfirmed, so it is
 * not guessed here.
 *
 * Signatures only, our own behaviour. See INSTRUCTIONS.md §13.
 */
package eu.kanade.tachiyomi.source.model

interface SManga {
    var url: String
    var title: String
    var artist: String?
    var author: String?
    var description: String?
    var genre: String?
    var status: Int
    var thumbnail_url: String?
    var update_strategy: UpdateStrategy
    var initialized: Boolean

    fun copyFrom(other: SManga) {
        if (other.author != null) author = other.author
        if (other.artist != null) artist = other.artist
        if (other.description != null) description = other.description
        if (other.genre != null) genre = other.genre
        if (other.thumbnail_url != null) thumbnail_url = other.thumbnail_url
        status = other.status
        update_strategy = other.update_strategy
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

        fun create(): SManga = SMangaImpl()
    }
}

class SMangaImpl : SManga {
    override lateinit var url: String
    override lateinit var title: String
    override var artist: String? = null
    override var author: String? = null
    override var description: String? = null
    override var genre: String? = null
    override var status: Int = 0
    override var thumbnail_url: String? = null
    override var update_strategy: UpdateStrategy = UpdateStrategy.ALWAYS_UPDATE
    override var initialized: Boolean = false
}

enum class UpdateStrategy { ALWAYS_UPDATE, ONLY_FETCH_ONCE }

interface SChapter {
    var url: String
    var name: String
    var date_upload: Long
    var chapter_number: Float
    var scanlator: String?

    fun copyFrom(other: SChapter) {
        name = other.name
        url = other.url
        date_upload = other.date_upload
        chapter_number = other.chapter_number
        scanlator = other.scanlator
    }

    companion object {
        fun create(): SChapter = SChapterImpl()
    }
}

class SChapterImpl : SChapter {
    override lateinit var url: String
    override lateinit var name: String
    override var date_upload: Long = 0
    override var chapter_number: Float = -1f
    override var scanlator: String? = null
}

open class Page(
    val index: Int,
    val url: String = "",
    var imageUrl: String? = null,
) {
    val number: Int get() = index + 1
}

class MangasPage(val mangas: List<SManga>, val hasNextPage: Boolean)

/**
 * Extensions build filter trees out of these to describe their search UI.
 * The host records what it is given and renders it itself; nothing here
 * performs filtering.
 */
sealed class Filter<T>(val name: String, var state: T) {
    abstract class Select<V>(
        name: String,
        val values: Array<V>,
        state: Int = 0,
    ) : Filter<Int>(name, state)

    abstract class Text(name: String, state: String = "") :
        Filter<String>(name, state)

    abstract class CheckBox(name: String, state: Boolean = false) :
        Filter<Boolean>(name, state)

    abstract class TriState(name: String, state: Int = STATE_IGNORE) :
        Filter<Int>(name, state) {
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
        Filter<List<V>>(name, state)

    abstract class Sort(
        name: String,
        val values: Array<String>,
        state: Selection? = null,
    ) : Filter<Sort.Selection?>(name, state) {
        data class Selection(val index: Int, val ascending: Boolean)
    }

    open class Header(name: String) : Filter<Any?>(name, null)
    open class Separator(name: String = "") : Filter<Any?>(name, null)
}

class FilterList(val list: List<Filter<*>>) : List<Filter<*>> by list {
    constructor(vararg fs: Filter<*>) : this(fs.asList())
}

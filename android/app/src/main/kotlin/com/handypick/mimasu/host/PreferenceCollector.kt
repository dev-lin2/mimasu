package com.handypick.mimasu.host

import android.content.Context
import android.content.SharedPreferences
import androidx.preference.CheckBoxPreference
import androidx.preference.EditTextPreference
import androidx.preference.ListPreference
import androidx.preference.MultiSelectListPreference
import androidx.preference.Preference
import androidx.preference.PreferenceGroup
import androidx.preference.PreferenceManager
import androidx.preference.PreferenceScreen
import androidx.preference.SwitchPreferenceCompat
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.ConfigurableAnimeSource

/**
 * Reads the preferences an extension declares, without showing them.
 *
 * `setupPreferenceScreen` is written for a settings Activity that does not
 * exist here: Flutter draws the UI. So the host builds a real
 * `PreferenceScreen`, hands it over, and then walks what the extension put in
 * it rather than attaching it to a fragment.
 *
 * The store matters as much as the shape. Extensions overwhelmingly read
 * their own settings with
 * `Injekt.get<Application>().getSharedPreferences("source_$id", 0)`, so the
 * screen is pointed at that same file. Writing anywhere else would produce a
 * settings page whose values the extension never sees.
 */
object PreferenceCollector {

    fun storeName(source: AnimeSource): String = "source_${source.id}"

    fun store(context: Context, source: AnimeSource): SharedPreferences =
        context.getSharedPreferences(storeName(source), Context.MODE_PRIVATE)

    /** Empty for a source that declares nothing, which is most of them. */
    fun collect(context: Context, source: AnimeSource): List<SourcePreference> {
        if (source !is ConfigurableAnimeSource) return emptyList()

        val screen = buildScreen(context, source)
        source.setupPreferenceScreen(screen)

        val out = mutableListOf<SourcePreference>()
        flatten(screen, out)
        return out
    }

    private fun buildScreen(
        context: Context,
        source: AnimeSource,
    ): PreferenceScreen {
        val manager = PreferenceManager(context)
        manager.sharedPreferencesName = storeName(source)
        manager.sharedPreferencesMode = Context.MODE_PRIVATE
        return manager.createPreferenceScreen(context)
    }

    /**
     * Groups are flattened rather than nested. An extension that categorises
     * its settings is describing its own layout, and the app has one of those
     * already.
     */
    private fun flatten(group: PreferenceGroup, out: MutableList<SourcePreference>) {
        for (i in 0 until group.preferenceCount) {
            when (val preference = group.getPreference(i)) {
                is PreferenceGroup -> flatten(preference, out)
                else -> describe(preference)?.let(out::add)
            }
        }
    }

    private fun describe(preference: Preference): SourcePreference? {
        val key = preference.key ?: return null
        if (key.isEmpty()) return null

        return when (preference) {
            is ListPreference -> SourcePreference(
                key = key,
                type = SourcePreferenceType.LIST,
                title = preference.title?.toString() ?: key,
                summary = preference.summary?.toString(),
                value = preference.value,
                entries = preference.entries?.map { it.toString() } ?: emptyList(),
                entryValues = preference.entryValues?.map { it.toString() }
                    ?: emptyList(),
            )

            is MultiSelectListPreference -> SourcePreference(
                key = key,
                type = SourcePreferenceType.MULTI_LIST,
                title = preference.title?.toString() ?: key,
                summary = preference.summary?.toString(),
                // Joined because the wire carries one string per value; the
                // Dart side splits on the same separator.
                value = preference.values.joinToString(SEPARATOR),
                entries = preference.entries?.map { it.toString() } ?: emptyList(),
                entryValues = preference.entryValues?.map { it.toString() }
                    ?: emptyList(),
            )

            // SwitchPreferenceCompat and CheckBoxPreference share a base, but
            // matching on the concrete types keeps this honest about what the
            // ecosystem actually uses.
            is SwitchPreferenceCompat -> toggle(key, preference, preference.isChecked)
            is CheckBoxPreference -> toggle(key, preference, preference.isChecked)

            is EditTextPreference -> SourcePreference(
                key = key,
                type = SourcePreferenceType.TEXT,
                title = preference.title?.toString() ?: key,
                summary = preference.summary?.toString(),
                value = preference.text,
                entries = emptyList(),
                entryValues = emptyList(),
            )

            // Reported rather than dropped: a control the app cannot draw is
            // worth showing as unsupported, so the user knows the source has
            // a setting they cannot reach from here.
            else -> SourcePreference(
                key = key,
                type = SourcePreferenceType.UNSUPPORTED,
                title = preference.title?.toString() ?: key,
                summary = preference.summary?.toString(),
                value = null,
                entries = emptyList(),
                entryValues = emptyList(),
            )
        }
    }

    private fun toggle(key: String, preference: Preference, checked: Boolean) =
        SourcePreference(
            key = key,
            type = SourcePreferenceType.TOGGLE,
            title = preference.title?.toString() ?: key,
            summary = preference.summary?.toString(),
            value = checked.toString(),
            entries = emptyList(),
            entryValues = emptyList(),
        )

    /**
     * Writes one value into the extension's own store.
     *
     * The type has to match what the extension will ask for: a
     * `SwitchPreferenceCompat` reads a boolean, and storing "true" as a string
     * throws `ClassCastException` inside the extension the next time it looks.
     */
    fun write(
        context: Context,
        source: AnimeSource,
        key: String,
        value: String,
        preferences: List<SourcePreference>,
    ) {
        val declared = preferences.firstOrNull { it.key == key } ?: return
        val editor = store(context, source).edit()
        when (declared.type) {
            SourcePreferenceType.TOGGLE ->
                editor.putBoolean(key, value.toBoolean())

            SourcePreferenceType.MULTI_LIST -> editor.putStringSet(
                key,
                value.split(SEPARATOR).filter { it.isNotEmpty() }.toSet(),
            )

            SourcePreferenceType.LIST,
            SourcePreferenceType.TEXT,
            -> editor.putString(key, value)

            SourcePreferenceType.UNSUPPORTED -> return
        }
        editor.apply()
    }

    /** Unlikely inside a preference value, and stable across both sides. */
    const val SEPARATOR = ""
}

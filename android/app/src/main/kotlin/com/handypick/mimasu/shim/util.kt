@file:Suppress("PackageDirectoryMismatch", "unused")

/*
 * eu.kanade.tachiyomi.util — response extensions extensions call, chiefly
 * asJsoup(). Confirmed referenced by a real extension
 * (docs/phase-0-findings.md §4).
 */
package eu.kanade.tachiyomi.util

import okhttp3.Response
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

fun Response.asJsoup(html: String? = null): Document = Jsoup.parse(
    html ?: body!!.string(),
    request.url.toString(),
)

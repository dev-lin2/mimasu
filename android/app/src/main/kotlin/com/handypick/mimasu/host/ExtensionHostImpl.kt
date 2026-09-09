package com.handypick.mimasu.host

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSourceFactory
import eu.kanade.tachiyomi.animesource.ConfigurableAnimeSource
import eu.kanade.tachiyomi.animesource.AnimeSource
import eu.kanade.tachiyomi.animesource.online.AnimeHttpSource
import eu.kanade.tachiyomi.network.RequestLog
import kotlinx.coroutines.runBlocking
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.ConfigurableSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.online.HttpSource
import dalvik.system.PathClassLoader
import java.security.MessageDigest

/**
 * Phase 0 extension host probe (INSTRUCTIONS.md section 5.3).
 *
 * This deliberately assumes nothing about Aniyomi's feature name or metadata
 * keys. Those are marked VERIFY in the spec because they were recalled rather
 * than confirmed, so this reads whatever an installed extension actually
 * declares and reports it back. Run it against a real extension and the true
 * values fall out.
 */
class ExtensionHostImpl(private val context: Context) : ExtensionHostApi {

    private val pm: PackageManager get() = context.packageManager

    /** Extension code runs here, never on the platform thread. */
    private val io = java.util.concurrent.Executors.newFixedThreadPool(2)

    override fun getHostInfo(): HostInfo = HostInfo(
        androidRelease = Build.VERSION.RELEASE ?: "unknown",
        sdkInt = Build.VERSION.SDK_INT.toLong(),
        hostPackage = context.packageName,
        canRequestPackageInstalls = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            pm.canRequestPackageInstalls()
        } else {
            true
        },
    )

    override fun canInstallPackages(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            pm.canRequestPackageInstalls()
        } else {
            true
        }

    /**
     * Declaring REQUEST_INSTALL_PACKAGES is not enough; the grant is per-app
     * and made by the user in system settings (INSTRUCTIONS.md 5.4). This
     * takes them straight there rather than asking them to go hunting.
     */
    override fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val intents = listOf(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}"),
            ),
            // Some devices refuse the package-scoped form and only accept the list.
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES),
        )
        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true
            } catch (_: Throwable) {
                // Try the next shape; report false only if none work.
            }
        }
        return false
    }

    override fun scanForExtensions(needles: List<String?>): List<ExtensionCandidate?> {
        val terms = needles.filterNotNull().map { it.lowercase() }
        if (terms.isEmpty()) return emptyList()

        val flags = PackageManager.GET_CONFIGURATIONS or
            PackageManager.GET_META_DATA or
            signingFlag()

        val packages: List<PackageInfo> = try {
            @Suppress("DEPRECATION")
            pm.getInstalledPackages(flags)
        } catch (t: Throwable) {
            // QUERY_ALL_PACKAGES may be refused; fail as an empty result, not a crash.
            return emptyList()
        }

        return packages.mapNotNull { info ->
            val features = info.reqFeatures?.mapNotNull { it.name } ?: emptyList()
            val metadata = info.applicationInfo?.metaData?.let { bundle ->
                bundle.keySet().associateWith { key ->
                    runCatching { bundle.get(key)?.toString() }.getOrNull()
                }
            } ?: emptyMap()

            val haystack = (features + metadata.keys).joinToString(" ").lowercase()
            if (terms.none { haystack.contains(it) }) return@mapNotNull null

            val appInfo = info.applicationInfo ?: return@mapNotNull null

            ExtensionCandidate(
                packageName = info.packageName,
                label = runCatching { pm.getApplicationLabel(appInfo).toString() }
                    .getOrDefault(info.packageName),
                versionName = info.versionName ?: "",
                versionCode = versionCodeOf(info),
                apkPath = appInfo.sourceDir ?: "",
                features = features,
                metadata = metadata,
                signatureSha256 = fingerprintOf(info),
            )
        }
    }

    /**
     * Loads source classes and interrogates them through the shim interfaces.
     *
     * The casts below are the point: because the extension's class loader is
     * parented on ours, the `HttpSource` it extends is *our* `HttpSource`, so
     * these are ordinary type checks rather than reflection. That type
     * identity across the loader boundary is what makes the whole design work
     * (INSTRUCTIONS.md 5.2).
     */
    override fun loadSources(
        packageName: String,
        classNames: List<String?>,
    ): List<LoadedSource?> {
        val wanted = classNames.filterNotNull()
        if (wanted.isEmpty()) return emptyList()

        ShimRegistry.ensureInitialised(context)

        val apkPath = runCatching {
            pm.getApplicationInfo(packageName, 0).sourceDir
        }.getOrNull()
        if (apkPath.isNullOrEmpty()) {
            return wanted.map { failedSource(it, "package not installed: $packageName") }
        }

        val loader = try {
            PathClassLoader(apkPath, javaClass.classLoader)
        } catch (t: Throwable) {
            return wanted.map { failedSource(it, "class loader failed: ${t.describe()}") }
        }

        val out = mutableListOf<LoadedSource?>()
        for (className in wanted) {
            try {
                val instance = Class.forName(qualify(packageName, className), false, loader)
                    .getDeclaredConstructor()
                    .apply { isAccessible = true }
                    .newInstance()

                // A factory yields several sources, usually one per language.
                val sources: List<Any> = when (instance) {
                    is AnimeSourceFactory -> instance.createSources()
                    is SourceFactory -> instance.createSources()
                    else -> listOf(instance)
                }

                for (source in sources) {
                    out += describe(className, source)
                }
            } catch (t: Throwable) {
                out += failedSource(className, t.describe())
            }
        }
        return out
    }

    /**
     * Asks a source for one page of popular titles, for real, over the
     * network. This is the end-to-end proof: extension code builds the
     * request, the host's client performs it, and extension code parses the
     * response back into shim types.
     *
     * Async, and it has to be: Pigeon dispatches host calls on the platform
     * main thread, where Android refuses network work outright. Doing this
     * synchronously earned a NetworkOnMainThreadException.
     */
    override fun fetchPopular(
        packageName: String,
        className: String,
        page: Long,
        callback: (Result<FetchResult>) -> Unit,
    ) {
        io.execute {
            callback(Result.success(fetchPopularBlocking(packageName, className, page)))
        }
    }

    private fun fetchPopularBlocking(
        packageName: String,
        className: String,
        page: Long,
    ): FetchResult {
        ShimRegistry.ensureInitialised(context)
        val started = System.nanoTime()

        fun failed(error: String) = FetchResult(
            ok = false,
            sourceName = "",
            items = emptyList(),
            hasNextPage = false,
            millis = (System.nanoTime() - started) / 1_000_000,
            error = error,
        )

        val apkPath = runCatching {
            pm.getApplicationInfo(packageName, 0).sourceDir
        }.getOrNull() ?: return failed("package not installed: $packageName")

        return try {
            val loader = PathClassLoader(apkPath, javaClass.classLoader)
            val instance = Class.forName(qualify(packageName, className), false, loader)
                .getDeclaredConstructor()
                .apply { isAccessible = true }
                .newInstance()

            val source = when (instance) {
                is AnimeSourceFactory -> instance.createSources().firstOrNull()
                else -> instance
            } ?: return failed("factory produced no sources")

            val catalogue = source as? AnimeCatalogueSource
                ?: return failed(
                    "not an AnimeCatalogueSource: ${source.javaClass.name}",
                )

            // The suspend orchestration in the shim is blocking underneath, so
            // driving it from here needs no coroutine machinery.
            val result = runBlocking { catalogue.getPopularAnime(page.toInt()) }

            FetchResult(
                ok = true,
                sourceName = catalogue.name,
                items = result.animes.map {
                    FetchedAnime(
                        title = it.title,
                        url = it.url,
                        thumbnailUrl = it.thumbnail_url,
                        description = it.description,
                    )
                },
                hasNextPage = result.hasNextPage,
                millis = (System.nanoTime() - started) / 1_000_000,
                error = null,
            )
        } catch (t: Throwable) {
            failed(t.describe())
        }
    }

    private fun describe(className: String, source: Any): LoadedSource {
        // Both flavours are handled: anime is what the app needs, manga is the
        // harness the shim was first verified against.
        val animeBase = source as? AnimeSource
        val mangaBase = source as? Source
        if (animeBase == null && mangaBase == null) {
            return failedSource(
                className,
                "loaded, but is neither an AnimeSource nor a Source: " +
                    source.javaClass.name,
            )
        }

        val animeCat = source as? AnimeCatalogueSource
        val animeHttp = source as? AnimeHttpSource
        val catalogue = source as? CatalogueSource
        val http = source as? HttpSource

        // Reading these runs extension code, so each is individually guarded:
        // a source with a throwing getter must not lose the whole result.
        fun <T> safe(fallback: T, block: () -> T): T =
            try { block() } catch (_: Throwable) { fallback }

        return LoadedSource(
            className = className,
            ok = true,
            sourceId = safe("") {
                (animeBase?.id ?: mangaBase?.id ?: 0L).toString()
            },
            name = safe("") { animeBase?.name ?: mangaBase?.name ?: "" },
            lang = safe("") { animeBase?.lang ?: mangaBase?.lang ?: "" },
            baseUrl = safe("") { animeHttp?.baseUrl ?: http?.baseUrl ?: "" },
            supportsLatest = safe(false) {
                animeCat?.supportsLatest ?: catalogue?.supportsLatest ?: false
            },
            configurable = source is ConfigurableAnimeSource ||
                source is ConfigurableSource,
            filterCount = safe(0L) {
                (animeCat?.getFilterList()?.size
                    ?: catalogue?.getFilterList()?.size
                    ?: 0).toLong()
            },
            error = null,
        )
    }

    private fun failedSource(className: String, error: String) = LoadedSource(
        className = className,
        ok = false,
        sourceId = "",
        name = "",
        lang = "",
        baseUrl = "",
        supportsLatest = false,
        configurable = false,
        filterCount = 0,
        error = error,
    )

    /**
     * Diagnostic. Extensions get their client from [NetworkHelper], which uses
     * Android's system trust store — unlike Dart's HTTP stack, which ships its
     * own CA bundle. When a source fails TLS this tells us whether the client
     * works at all, so a stale device trust store is not mistaken for a broken
     * shim.
     */
    override fun hostHttpCheck(url: String, callback: (Result<String>) -> Unit) {
        io.execute {
            ShimRegistry.ensureInitialised(context)
            val result = try {
                val helper = uy.kohesive.injekt.Injekt
                    .getInstance(eu.kanade.tachiyomi.network.NetworkHelper::class.java)
                val request = okhttp3.Request.Builder().url(url).build()
                helper.client.newCall(request).execute().use { response ->
                    "HTTP ${response.code}, ${response.body?.contentLength() ?: -1} bytes"
                }
            } catch (t: Throwable) {
                "FAILED ${t.describe()}"
            }
            callback(Result.success(result))
        }
    }

    override fun requestLogHostCounts(): Map<String?, Long?> =
        RequestLog.hostCounts().mapValues { it.value.toLong() }

    override fun probeClasses(
        packageName: String,
        classNames: List<String?>,
    ): List<ClassProbeResult?> {
        val wanted = classNames.filterNotNull()
        if (wanted.isEmpty()) return emptyList()

        val apkPath = runCatching {
            pm.getApplicationInfo(packageName, 0).sourceDir
        }.getOrNull()

        if (apkPath.isNullOrEmpty()) {
            return wanted.map {
                ClassProbeResult(
                    className = it,
                    loaded = false,
                    instantiated = false,
                    superclasses = emptyList(),
                    error = "package not installed: $packageName",
                )
            }
        }

        // Injekt has to be populated before a source constructor runs, since
        // that constructor is what asks for NetworkHelper (5.2).
        ShimRegistry.ensureInitialised(context)

        // One class loader per extension, parented on ours so the shim classes
        // resolve from here (INSTRUCTIONS.md 5.2).
        val loader = try {
            PathClassLoader(apkPath, javaClass.classLoader)
        } catch (t: Throwable) {
            return wanted.map {
                ClassProbeResult(
                    className = it,
                    loaded = false,
                    instantiated = false,
                    superclasses = emptyList(),
                    error = "class loader failed: ${t.describe()}",
                )
            }
        }

        return wanted.map { className ->
            probeOne(loader, qualify(packageName, className))
        }
    }

    private fun probeOne(loader: ClassLoader, className: String): ClassProbeResult {
        val klass = try {
            Class.forName(className, false, loader)
        } catch (t: Throwable) {
            return ClassProbeResult(
                className = className,
                loaded = false,
                instantiated = false,
                superclasses = emptyList(),
                error = t.describe(),
            )
        }

        // Ancestry is the payload we actually care about: it names the
        // extensions-lib types the host has to supply.
        val ancestry = mutableListOf<String>()
        runCatching {
            var current: Class<*>? = klass.superclass
            while (current != null && current != Any::class.java) {
                ancestry += current.name
                current = current.superclass
            }
            klass.interfaces.forEach { ancestry += "interface ${it.name}" }
        }

        var instantiated = false
        var error: String? = null
        try {
            klass.getDeclaredConstructor().apply { isAccessible = true }.newInstance()
            instantiated = true
        } catch (t: Throwable) {
            // Expected until the shim exists. NoClassDefFoundError here is the
            // single most informative failure in Phase 0.
            error = t.describe()
        }

        return ClassProbeResult(
            className = className,
            loaded = true,
            instantiated = instantiated,
            superclasses = ancestry,
            error = error,
        )
    }

    /**
     * Metadata class names may be relative: a leading dot means "inside this
     * package", so `.AnimeOnsen` in package `…animeextension.all.animeonsen`
     * means `…animeextension.all.animeonsen.AnimeOnsen`. Confirmed against a
     * real anime extension, which fails to load without this.
     */
    private fun qualify(packageName: String, className: String): String =
        if (className.startsWith(".")) packageName + className else className

    private fun signingFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }

    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }

    /** SHA-256 of the signing certificate, uppercase colon-separated hex. */
    private fun fingerprintOf(info: PackageInfo): String {
        val raw: ByteArray? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.signingInfo?.let { signing ->
                val certs = if (signing.hasMultipleSigners()) {
                    signing.apkContentsSigners
                } else {
                    signing.signingCertificateHistory
                }
                certs?.firstOrNull()?.toByteArray()
            }
        } else {
            @Suppress("DEPRECATION")
            info.signatures?.firstOrNull()?.toByteArray()
        }

        if (raw == null) return ""
        val digest = MessageDigest.getInstance("SHA-256").digest(raw)
        return digest.joinToString(":") { "%02X".format(it) }
    }

    private fun Throwable.describe(): String {
        val cause = cause?.let { " <- ${it.javaClass.simpleName}: ${it.message}" } ?: ""
        return "${javaClass.simpleName}: ${message ?: "no message"}$cause"
    }
}

package com.handypick.mimasu.host

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
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

        // One class loader per extension, parented on ours so the shim classes
        // we eventually provide resolve from here (INSTRUCTIONS.md 5.2).
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

        return wanted.map { className -> probeOne(loader, className) }
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

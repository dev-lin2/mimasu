package com.handypick.mimasu.host

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import java.io.File
import java.security.MessageDigest

/**
 * Reading and installing extension APKs (INSTRUCTIONS.md §5.4, §5.5).
 *
 * Mimasu never installs anything itself: it hands the file to Android's
 * package installer, which shows its own confirmation. That is both the only
 * supported path and the honest one — the README promises nothing installs
 * silently.
 */
class ApkInstaller(private val context: Context) {

    private val pm: PackageManager get() = context.packageManager

    /**
     * Reads an APK without installing it, so the signing key can be checked
     * before the user is asked to trust anything.
     */
    fun inspect(filePath: String): ApkInfo {
        val file = File(filePath)
        if (!file.exists()) return failed("no file at $filePath")

        val flags = PackageManager.GET_CONFIGURATIONS or
            PackageManager.GET_META_DATA or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                PackageManager.GET_SIGNING_CERTIFICATES
            } else {
                @Suppress("DEPRECATION")
                PackageManager.GET_SIGNATURES
            }

        @Suppress("DEPRECATION")
        val info: PackageInfo = pm.getPackageArchiveInfo(filePath, flags)
            ?: return failed("not a readable APK")

        // getPackageArchiveInfo leaves these unset, and getApplicationLabel
        // needs them to resolve resources out of the file.
        val appInfo = info.applicationInfo
        appInfo?.sourceDir = filePath
        appInfo?.publicSourceDir = filePath

        val metadata = appInfo?.metaData?.let { bundle ->
            bundle.keySet().associateWith {
                runCatching { bundle.get(it)?.toString() }.getOrNull()
            }
        } ?: emptyMap()

        return ApkInfo(
            ok = true,
            packageName = info.packageName ?: "",
            label = appInfo
                ?.let { runCatching { pm.getApplicationLabel(it).toString() }.getOrNull() }
                ?: info.packageName.orEmpty(),
            versionName = info.versionName ?: "",
            versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            },
            signatureSha256 = fingerprint(info),
            features = info.reqFeatures?.mapNotNull { it.name } ?: emptyList(),
            metadata = metadata,
            error = null,
        )
    }

    /**
     * The APK lives in our own storage, so the installer cannot read it by
     * path — it needs a content:// URI granted read permission. That is what
     * the FileProvider in the manifest is for.
     */
    fun install(filePath: String): Boolean {
        val file = File(filePath)
        if (!file.exists()) return false

        val uri: Uri = try {
            FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file,
            )
        } catch (_: Throwable) {
            return false
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    fun uninstall(packageName: String): Boolean {
        val intent = Intent(Intent.ACTION_DELETE).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(intent)
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** Lowercase hex with no separators, to compare against an index directly. */
    private fun fingerprint(info: PackageInfo): String {
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
        return MessageDigest.getInstance("SHA-256").digest(raw)
            .joinToString("") { "%02x".format(it) }
    }

    private fun failed(error: String) = ApkInfo(
        ok = false,
        packageName = "",
        label = "",
        versionName = "",
        versionCode = 0,
        signatureSha256 = "",
        features = emptyList(),
        metadata = emptyMap(),
        error = error,
    )
}

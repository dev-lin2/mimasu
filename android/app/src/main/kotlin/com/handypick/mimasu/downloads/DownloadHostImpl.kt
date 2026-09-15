package com.handypick.mimasu.downloads

import android.content.Context
import com.handypick.mimasu.host.DownloadAccepted
import com.handypick.mimasu.host.DownloadHostApi
import com.handypick.mimasu.host.DownloadRefusal
import com.handypick.mimasu.host.DownloadRequest
import com.handypick.mimasu.host.DownloadState
import com.handypick.mimasu.host.DownloadStatus

/**
 * The pigeon surface over [DownloadEngine].
 *
 * Nothing here blocks: every method is `@async` on the Dart side and the
 * engine's own work happens on its worker thread, so these calls only move
 * state across the boundary.
 */
class DownloadHostImpl(private val context: Context) : DownloadHostApi {

    init {
        DownloadEngine.initialise(context)
    }

    override fun enqueueDownload(
        request: DownloadRequest,
        wifiOnly: Boolean,
        callback: (Result<DownloadAccepted>) -> Unit,
    ) {
        val result = runCatching {
            val transfer = DownloadEngine.Transfer(
                id = request.id,
                url = request.url,
                headers = request.headers
                    .filterKeys { it != null }
                    .filterValues { it != null }
                    .map { (k, v) -> k!! to v!! }
                    .toMap(),
                fileName = request.fileName,
                title = request.title,
                subtitle = request.subtitle,
            )
            val refusal = DownloadEngine.enqueue(transfer, wifiOnly)
            if (refusal == DownloadEngine.Refusal.NONE) {
                DownloadService.ensureRunning(context)
            }
            DownloadAccepted(
                accepted = refusal == DownloadEngine.Refusal.NONE,
                refusal = refusal.toPigeon(),
            )
        }
        callback(result)
    }

    override fun cancelDownload(id: String, callback: (Result<Unit>) -> Unit) {
        callback(runCatching { DownloadEngine.cancel(id) })
    }

    override fun removeDownload(id: String, callback: (Result<Unit>) -> Unit) {
        callback(runCatching { DownloadEngine.remove(id) })
    }

    override fun listDownloads(
        callback: (Result<List<DownloadStatus>>) -> Unit,
    ) {
        callback(
            runCatching {
                DownloadEngine.snapshot().map { it.toStatus() }
            },
        )
    }

    override fun isMeteredConnection(callback: (Result<Boolean>) -> Unit) {
        callback(runCatching { DownloadEngine.isMetered(context) })
    }

    private fun DownloadEngine.Transfer.toStatus() = DownloadStatus(
        id = id,
        state = state.toPigeon(),
        bytesDownloaded = bytes,
        totalBytes = total,
        filePath = filePath,
        error = error,
    )

    private fun DownloadEngine.State.toPigeon() = when (this) {
        DownloadEngine.State.QUEUED -> DownloadState.QUEUED
        DownloadEngine.State.RUNNING -> DownloadState.RUNNING
        DownloadEngine.State.COMPLETED -> DownloadState.COMPLETED
        DownloadEngine.State.FAILED -> DownloadState.FAILED
        DownloadEngine.State.CANCELLED -> DownloadState.CANCELLED
    }

    private fun DownloadEngine.Refusal.toPigeon() = when (this) {
        DownloadEngine.Refusal.NONE -> DownloadRefusal.NONE
        DownloadEngine.Refusal.METERED -> DownloadRefusal.METERED
        DownloadEngine.Refusal.UNSUPPORTED_FORMAT ->
            DownloadRefusal.UNSUPPORTED_FORMAT
    }
}

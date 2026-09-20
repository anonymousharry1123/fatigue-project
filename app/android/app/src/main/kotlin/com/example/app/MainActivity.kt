package com.example.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

class MainActivity : FlutterActivity() {
    private data class PendingBackup(
        val json: String?,
        val requestCode: Int,
        val result: MethodChannel.Result,
        var processing: Boolean = false,
    )
    private var pendingBackup: PendingBackup? = null
    private val createBackupRequest = 48017
    private val openBackupRequest = 48018
    private val maximumBackupBytes = 20 * 1024 * 1024
    private class BackupTooLargeException : Exception()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tonyo/timezone")
            .setMethodCallHandler { call, result ->
                if (call.method == "getTimezone") {
                    result.success(TimeZone.getDefault().id)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tonyo/device_backup")
            .setMethodCallHandler { call, result ->
                if (call.method != "save" && call.method != "open") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingBackup != null) {
                    result.error("backup_busy", "A backup file dialog is already open.", null)
                    return@setMethodCallHandler
                }
                if (call.method == "open") {
                    pendingBackup = PendingBackup(null, openBackupRequest, result)
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "application/json"
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    try {
                        startActivityForResult(intent, openBackupRequest)
                    } catch (_: Exception) {
                        pendingBackup = null
                        result.error("backup_unavailable", "The open dialog is unavailable.", null)
                    }
                    return@setMethodCallHandler
                }
                val json = call.argument<String>("json")
                val filename = call.argument<String>("filename")
                if (json == null || filename.isNullOrBlank() || !filename.endsWith(".json") ||
                    filename.any { it == '/' || it == '\\' || it.isISOControl() }
                ) {
                    result.error("backup_invalid", "The backup file is invalid.", null)
                    return@setMethodCallHandler
                }
                pendingBackup = PendingBackup(json, createBackupRequest, result)
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "application/json"
                    putExtra(Intent.EXTRA_TITLE, filename)
                }
                try {
                    startActivityForResult(intent, createBackupRequest)
                } catch (_: Exception) {
                    pendingBackup = null
                    result.error("backup_unavailable", "The save dialog is unavailable.", null)
                }
            }
    }

    @Deprecated("Required to receive the system document picker result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != createBackupRequest && requestCode != openBackupRequest) return
        val backup = pendingBackup ?: return
        if (requestCode != backup.requestCode || backup.processing) return
        if (resultCode == Activity.RESULT_CANCELED) {
            pendingBackup = null
            backup.result.success(if (requestCode == openBackupRequest) null else false)
            return
        }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingBackup = null
            backup.result.error("backup_failed", "The selected file is unavailable.", null)
            return
        }
        backup.processing = true
        if (requestCode == openBackupRequest) {
            Thread {
                var json: String? = null
                var failureCode: String? = null
                var failureMessage: String? = null
                try {
                    json = readBackup(uri)
                } catch (_: BackupTooLargeException) {
                    failureCode = "backup_too_large"
                    failureMessage = "Choose a backup of 20 MiB or smaller."
                } catch (_: CharacterCodingException) {
                    failureCode = "backup_invalid_encoding"
                    failureMessage = "The backup must be a UTF-8 JSON file."
                } catch (_: Exception) {
                    failureCode = "backup_failed"
                    failureMessage = "The backup could not be opened. Please try again."
                }
                runOnUiThread {
                    if (pendingBackup === backup) {
                        pendingBackup = null
                        val code = failureCode
                        if (code != null) {
                            backup.result.error(code, failureMessage, null)
                        } else {
                            backup.result.success(json)
                        }
                    }
                }
            }.start()
            return
        }
        // Document providers may perform slow I/O. Keep the UI responsive and
        // confirm success only after the full UTF-8 file is written and closed.
        Thread {
            var saved = false
            try {
                val output = contentResolver.openOutputStream(uri, "wt")
                    ?: throw java.io.IOException("The destination cannot be opened.")
                output.use { it.write(requireNotNull(backup.json).toByteArray(Charsets.UTF_8)) }
                saved = true
            } catch (_: Exception) {
                // ACTION_CREATE_DOCUMENT created a new document. Remove an
                // incomplete copy when its provider supports deletion.
                try { DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) {}
            }
            runOnUiThread {
                if (pendingBackup === backup) {
                    pendingBackup = null
                    if (saved) {
                        backup.result.success(true)
                    } else {
                        backup.result.error("backup_failed", "The backup could not be saved. Please try again.", null)
                    }
                }
            }
        }.start()
    }

    private fun readBackup(uri: Uri): String {
        // A provider may omit or misreport the size, so check the metadata and
        // also cap the stream before appending each chunk to memory.
        contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
            val column = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (column >= 0 && cursor.moveToFirst() && !cursor.isNull(column) &&
                cursor.getLong(column) > maximumBackupBytes
            ) {
                throw BackupTooLargeException()
            }
        }
        val input = contentResolver.openInputStream(uri)
            ?: throw java.io.IOException("The selected file cannot be opened.")
        val bytes = ByteArrayOutputStream()
        input.use { stream ->
            val buffer = ByteArray(8192)
            while (true) {
                val read = stream.read(buffer, 0, minOf(buffer.size, maximumBackupBytes - bytes.size() + 1))
                if (read < 0) break
                if (bytes.size() + read > maximumBackupBytes) throw BackupTooLargeException()
                bytes.write(buffer, 0, read)
            }
        }
        return Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes.toByteArray()))
            .toString()
    }

    override fun onDestroy() {
        pendingBackup?.result?.error("backup_interrupted", "The backup operation was interrupted. Please try again.", null)
        pendingBackup = null
        super.onDestroy()
    }
}

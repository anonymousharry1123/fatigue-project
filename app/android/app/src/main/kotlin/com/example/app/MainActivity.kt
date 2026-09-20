package com.example.app

import android.app.Activity
import android.content.Intent
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private data class PendingBackup(val json: String, val result: MethodChannel.Result)
    private var pendingBackup: PendingBackup? = null
    private val createBackupRequest = 48017

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
                if (call.method != "save") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                if (pendingBackup != null) {
                    result.error("backup_busy", "A backup is already being saved.", null)
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
                pendingBackup = PendingBackup(json, result)
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
        if (requestCode != createBackupRequest) return
        val backup = pendingBackup ?: return
        if (resultCode == Activity.RESULT_CANCELED) {
            pendingBackup = null
            backup.result.success(false)
            return
        }
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pendingBackup = null
            backup.result.error("backup_failed", "The save location is unavailable.", null)
            return
        }
        // Document providers may perform slow I/O. Keep the UI responsive and
        // confirm success only after the full UTF-8 file is written and closed.
        Thread {
            var saved = false
            try {
                val output = contentResolver.openOutputStream(uri, "wt")
                    ?: throw java.io.IOException("The destination cannot be opened.")
                output.use { it.write(backup.json.toByteArray(Charsets.UTF_8)) }
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

    override fun onDestroy() {
        pendingBackup?.result?.error("backup_interrupted", "Saving was interrupted. Please try again.", null)
        pendingBackup = null
        super.onDestroy()
    }
}

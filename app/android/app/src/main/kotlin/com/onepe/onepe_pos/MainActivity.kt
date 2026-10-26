package com.onepe.onepe_pos

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var printer: PrinterChannel
    private var pending: Pair<MethodCall, MethodChannel.Result>? = null
    private var folderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        printer = PrinterChannel(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PrinterChannel.NAME).setMethodCallHandler { call, result ->
            // Android 12+: Bluetooth printers need the runtime BLUETOOTH_CONNECT permission.
            if (PrinterChannel.needsBluetooth(call.method) && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
            ) {
                pending?.second?.error("BUSY", "Waiting for Bluetooth permission", null)
                pending = call to result
                requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), BT_REQUEST)
            } else {
                printer.onMethodCall(call, result)
            }
        }
        // Offline bill backup files. "pickFolder" asks once for the backup folder (Android 10+: folder chooser,
        // older: storage permission) and returns its name, or null when the user declines.
        val backup = OfflineBackup(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OfflineBackup.NAME).setMethodCallHandler { call, result ->
            if (call.method != "pickFolder") return@setMethodCallHandler backup.onMethodCall(call, result)
            folderResult?.success(null)
            folderResult = result
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startActivityForResult(OfflineBackup.pickIntent(this), FOLDER_REQUEST)
            } else {
                requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), STORAGE_REQUEST)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != FOLDER_REQUEST) return
        val result = folderResult ?: return
        folderResult = null
        val tree = data?.data
        if (resultCode != RESULT_OK || tree == null) return result.success(null)
        try {
            OfflineBackup.keepFolder(this, tree)
            result.success(DocumentsContract.getTreeDocumentId(tree).substringAfter(':'))
        } catch (e: Exception) {
            result.error("BACKUP_FAILED", e.message, null)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_REQUEST) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            folderResult?.success(if (granted) OfflineBackup.FOLDER else null)
            folderResult = null
            return
        }
        if (requestCode != BT_REQUEST) return
        val (call, result) = pending ?: return
        pending = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) printer.onMethodCall(call, result)
        else result.error("PERMISSION", "Allow Nearby devices (Bluetooth) permission to use a Bluetooth printer", null)
    }

    private companion object {
        const val BT_REQUEST = 7101
        const val STORAGE_REQUEST = 7102
        const val FOLDER_REQUEST = 7103
    }
}

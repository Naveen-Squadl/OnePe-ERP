package com.onepe.onepe_pos

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var printer: PrinterChannel
    private var pending: Pair<MethodCall, MethodChannel.Result>? = null

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
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != BT_REQUEST) return
        val (call, result) = pending ?: return
        pending = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) printer.onMethodCall(call, result)
        else result.error("PERMISSION", "Allow Nearby devices (Bluetooth) permission to use a Bluetooth printer", null)
    }

    private companion object {
        const val BT_REQUEST = 7101
    }
}

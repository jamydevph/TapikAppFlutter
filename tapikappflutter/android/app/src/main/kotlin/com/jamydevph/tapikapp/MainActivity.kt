package com.jamydevph.tapikapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bluetooth: BtHidBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bluetooth = BtHidBridge(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BtHidBridge.CHANNEL),
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bluetooth?.onPermissionResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        bluetooth?.dispose()
        bluetooth = null
        super.onDestroy()
    }
}

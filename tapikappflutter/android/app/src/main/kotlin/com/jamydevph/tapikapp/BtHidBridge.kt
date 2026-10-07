package com.jamydevph.tapikapp

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

@SuppressLint("MissingPermission")
class BtHidBridge(private val activity: Activity, private val channel: MethodChannel) {
    companion object {
        const val CHANNEL = "tapikapp/bt_hid"
        private const val PERMISSION_REQUEST = 4207
        private const val SUBCLASS_COMBO: Byte = 0xC0.toByte()
    }

    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val adapter: BluetoothAdapter? =
        (activity.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var proxy: BluetoothHidDevice? = null
    private var host: BluetoothDevice? = null
    private var registered = false
    private var pendingRegister: MethodChannel.Result? = null
    private var pendingName = "Tapikapp"
    private var pendingDescriptor = ByteArray(0)

    init {
        channel.setMethodCallHandler(::onCall)
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(adapter != null)
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> {
                requestPermission()
                result.success(null)
            }
            "bondedHosts" -> result.success(bondedHosts())
            "register" -> register(call, result)
            "connect" -> connect(call.argument<String>("address"), result)
            "send" -> send(call, result)
            "disconnect" -> {
                disconnect()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun requiredPermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE)
        } else {
            emptyArray()
        }

    private fun hasPermission(): Boolean = requiredPermissions().all {
        activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestPermission() {
        val missing = requiredPermissions().filter {
            activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    private fun bondedHosts(): List<Map<String, String>> {
        if (!hasPermission()) return emptyList()
        return adapter?.bondedDevices.orEmpty().map {
            mapOf("address" to it.address, "name" to (it.name ?: it.address))
        }
    }

    private fun register(call: MethodCall, result: MethodChannel.Result) {
        val bluetooth = adapter
        if (bluetooth == null) {
            result.error("unsupported", "This phone has no Bluetooth.", null)
            return
        }
        if (!hasPermission()) {
            result.error("permission", "Bluetooth permission was not granted.", null)
            return
        }
        if (registered) {
            result.success(true)
            return
        }
        pendingName = call.argument<String>("name") ?: "Tapikapp"
        pendingDescriptor = call.argument<ByteArray>("descriptor") ?: ByteArray(0)
        pendingRegister = result
        val existing = proxy
        if (existing != null) {
            registerApp(existing)
            return
        }
        val opened = bluetooth.getProfileProxy(activity, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, service: BluetoothProfile) {
                val hid = service as BluetoothHidDevice
                proxy = hid
                registerApp(hid)
            }

            override fun onServiceDisconnected(profile: Int) {
                proxy = null
                registered = false
                emitState("disconnected")
            }
        }, BluetoothProfile.HID_DEVICE)
        if (!opened) {
            pendingRegister = null
            result.error("unsupported", "This phone cannot act as a Bluetooth keyboard.", null)
        }
    }

    private fun registerApp(hid: BluetoothHidDevice) {
        val sdp = BluetoothHidDeviceAppSdpSettings(
            pendingName,
            "Tapikapp keyboard and trackpad",
            "Tapikapp",
            SUBCLASS_COMBO,
            pendingDescriptor,
        )
        val accepted = hid.registerApp(sdp, null, null, executor, callback)
        if (!accepted) finishRegister(false)
    }

    private fun finishRegister(success: Boolean) {
        val result = pendingRegister ?: return
        pendingRegister = null
        main.post { result.success(success) }
    }

    private val callback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            this@BtHidBridge.registered = registered
            finishRegister(registered)
        }

        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            when (state) {
                BluetoothProfile.STATE_CONNECTED -> {
                    host = device
                    emitState("connected")
                }
                BluetoothProfile.STATE_CONNECTING -> emitState("connecting")
                BluetoothProfile.STATE_DISCONNECTED -> {
                    if (host?.address == device.address) host = null
                    emitState("disconnected")
                }
            }
        }
    }

    private fun connect(address: String?, result: MethodChannel.Result) {
        val hid = proxy
        val bluetooth = adapter
        if (hid == null || bluetooth == null || !registered) {
            result.error("not_registered", "Bluetooth keyboard mode is not ready.", null)
            return
        }
        if (address == null || !BluetoothAdapter.checkBluetoothAddress(address)) {
            result.error("bad_address", "That is not a Bluetooth address.", null)
            return
        }
        result.success(hid.connect(bluetooth.getRemoteDevice(address)))
    }

    private fun send(call: MethodCall, result: MethodChannel.Result) {
        val hid = proxy
        val target = host
        val reports = call.argument<List<Any>>("reports")
        if (hid == null || target == null || reports == null) {
            result.success(false)
            return
        }
        var sent = true
        for (entry in reports) {
            val pair = entry as? List<*> ?: continue
            val id = (pair[0] as? Int) ?: continue
            val data = pair[1] as? ByteArray ?: continue
            if (!hid.sendReport(target, id, data)) sent = false
        }
        result.success(sent)
    }

    private fun disconnect() {
        val hid = proxy ?: return
        host?.let { hid.disconnect(it) }
    }

    private fun emitState(state: String) {
        main.post { channel.invokeMethod("onState", state) }
    }

    fun dispose() {
        val hid = proxy
        if (hid != null) {
            host?.let { hid.disconnect(it) }
            if (registered) hid.unregisterApp()
            adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, hid)
        }
        proxy = null
        host = null
        registered = false
        executor.shutdown()
    }
}

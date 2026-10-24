package com.jamydevph.tapikapp

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
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
    private var pendingHost: BluetoothDevice? = null
    private var registered = false
    private var unregistering = false
    private var registering = false
    private var proxyRequested = false
    private var cancelRegister = false
    private var askedBefore = false
    private var rationaleBefore = false
    private var pendingRegister: MethodChannel.Result? = null
    private var pendingName = "Tapikapp"
    private var pendingDescriptor = ByteArray(0)

    private val changes = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            emitHostsChanged()
        }
    }

    init {
        channel.setMethodCallHandler(::onCall)
        val filter = IntentFilter().apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.registerReceiver(changes, filter, Context.RECEIVER_EXPORTED)
        } else {
            activity.registerReceiver(changes, filter)
        }
    }

    private fun onCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(adapter != null)
            "isEnabled" -> result.success(adapter?.isEnabled == true)
            "hasPermission" -> result.success(hasPermission())
            "requestPermission" -> {
                requestPermission()
                result.success(null)
            }
            "openBluetoothSettings" -> result.success(open(Intent(Settings.ACTION_BLUETOOTH_SETTINGS)))
            "openAppSettings" -> result.success(
                open(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.packageName, null),
                    ),
                ),
            )
            "bondedHosts" -> result.success(bondedHosts())
            "register" -> register(call, result)
            "connect" -> connect(call.argument<String>("address"), result)
            "send" -> send(call, result)
            "disconnect" -> {
                disconnect()
                result.success(null)
            }
            "unregister" -> {
                unregister()
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
        if (missing.isEmpty()) return
        rationaleBefore = missing.any { activity.shouldShowRequestPermissionRationale(it) }
        activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    fun onPermissionResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val deniedBefore = askedBefore || rationaleBefore
        askedBefore = true
        val outcome = when {
            hasPermission() -> "granted"
            grantResults.isEmpty() || !deniedBefore -> "denied"
            permissions.any {
                activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED &&
                    !activity.shouldShowRequestPermissionRationale(it)
            } -> "blocked"
            else -> "denied"
        }
        main.post { channel.invokeMethod("onPermission", outcome) }
    }

    private fun open(intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (error: ActivityNotFoundException) {
        false
    }

    private fun bondedHosts(): List<Map<String, String>> {
        if (!hasPermission()) return emptyList()
        return adapter?.bondedDevices.orEmpty()
            .filter { it.bluetoothClass?.majorDeviceClass == BluetoothClass.Device.Major.COMPUTER }
            .map { mapOf("address" to it.address, "name" to (it.name ?: it.address)) }
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
        finishRegister(false)
        pendingRegister = result
        cancelRegister = false
        if (registering || proxyRequested) return
        val existing = proxy
        if (existing != null) {
            registerApp(existing)
            return
        }
        proxyRequested = true
        val opened = bluetooth.getProfileProxy(activity, object : BluetoothProfile.ServiceListener {
            override fun onServiceConnected(profile: Int, service: BluetoothProfile) {
                val hid = service as BluetoothHidDevice
                proxy = hid
                proxyRequested = false
                if (pendingRegister != null) registerApp(hid)
            }

            override fun onServiceDisconnected(profile: Int) {
                proxy = null
                host = null
                pendingHost = null
                registered = false
                unregistering = false
                registering = false
                proxyRequested = false
                cancelRegister = false
                finishRegister(false)
                emitState("disconnected")
            }
        }, BluetoothProfile.HID_DEVICE)
        if (!opened) {
            proxyRequested = false
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
        if (accepted) registering = true else finishRegister(false)
    }

    private fun finishRegister(success: Boolean) {
        val result = pendingRegister ?: return
        pendingRegister = null
        main.post { result.success(success) }
    }

    private val callback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            registering = false
            this@BtHidBridge.registered = registered
            if (!registered && unregistering) {
                unregistering = false
                return
            }
            if (registered && cancelRegister) {
                cancelRegister = false
                if (proxy?.unregisterApp() == true) unregistering = true
                this@BtHidBridge.registered = false
                return
            }
            finishRegister(registered)
        }

        override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
            when (state) {
                BluetoothProfile.STATE_CONNECTED -> {
                    host = device
                    if (pendingHost?.address == device.address) pendingHost = null
                    emitState("connected", device)
                }
                BluetoothProfile.STATE_CONNECTING -> emitState("connecting", device)
                BluetoothProfile.STATE_DISCONNECTED -> {
                    if (host?.address == device.address) host = null
                    if (pendingHost?.address == device.address) pendingHost = null
                    emitState("disconnected", device)
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
        val device = bluetooth.getRemoteDevice(address)
        val accepted = hid.connect(device)
        if (accepted) pendingHost = device
        result.success(accepted)
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
        (host ?: pendingHost)?.let { hid.disconnect(it) }
    }

    private fun unregister() {
        if (registering || proxyRequested) {
            cancelRegister = true
            finishRegister(false)
        }
        val hid = proxy ?: return
        disconnect()
        if (registered && hid.unregisterApp()) unregistering = true
        registered = false
    }

    private fun emitState(state: String, device: BluetoothDevice? = null) {
        val event = mapOf(
            "state" to state,
            "address" to device?.address,
            "name" to (device?.name ?: device?.address),
        )
        main.post { channel.invokeMethod("onState", event) }
    }

    private fun emitHostsChanged() {
        main.post { channel.invokeMethod("onHostsChanged", null) }
    }

    fun dispose() {
        runCatching { activity.unregisterReceiver(changes) }
        val hid = proxy
        if (hid != null) {
            host?.let { hid.disconnect(it) }
            if (registered) hid.unregisterApp()
            adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, hid)
        }
        proxy = null
        host = null
        pendingHost = null
        registered = false
        executor.shutdown()
    }
}

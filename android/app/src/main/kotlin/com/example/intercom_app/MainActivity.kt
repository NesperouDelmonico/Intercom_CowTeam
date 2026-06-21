package com.example.intercom_app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.intercom_app/audio"
    private val WIFI_DIRECT_CHANNEL = "com.example.intercom_app/wifidirect"
    private val WIFI_DIRECT_EVENTS  = "com.example.intercom_app/wifidirect_events"

    private var audioManager: AudioManager? = null
    private var bluetoothHeadset: BluetoothHeadset? = null
    private var isBtActive = false
    private lateinit var wifiDirect: WifiDirectService

    private val headsetListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile == BluetoothProfile.HEADSET) {
                bluetoothHeadset = proxy as BluetoothHeadset
            }
        }
        override fun onServiceDisconnected(profile: Int) {
            bluetoothHeadset = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Permitir ejecución con pantalla bloqueada
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        BluetoothAdapter.getDefaultAdapter()
            ?.getProfileProxy(this, headsetListener, BluetoothProfile.HEADSET)

        // ── Canal de sala (CallForegroundService) ──────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            CallForegroundService.METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCallWithService" -> {
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_START
                            putExtra("deviceName", call.argument<String>("deviceName"))
                            putExtra("myIp",       call.argument<String>("myIp"))
                            putExtra("myName",     call.argument<String>("myName"))
                            putExtra("myAvatar",   call.argument<String>("myAvatar") ?: "")
                            putExtra("roomCode",   call.argument<String>("roomCode"))
                        }
                        startForegroundServiceCompat(intent)
                        result.success(null)
                    }
                    "stopCall" -> {
                        sendCommandToService("stopCall")
                        result.success(null)
                    }
                    "setGain" -> {
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_COMMAND
                            putExtra("command", "setGain")
                            putExtra("gain",
                                call.argument<Double>("gain")?.toFloat() ?: 1.0f)
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "setVox" -> {
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_COMMAND
                            putExtra("command",   "setVox")
                            putExtra("enabled",   call.argument<Boolean>("enabled") ?: false)
                            putExtra("threshold", call.argument<Double>("threshold") ?: 500.0)
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "setMuted" -> {
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_COMMAND
                            putExtra("command", "setMuted")
                            putExtra("muted", call.argument<Boolean>("muted") ?: false)
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "setMemberMuted" -> {
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_COMMAND
                            putExtra("command", "setMemberMuted")
                            putExtra("ip",    call.argument<String>("ip"))
                            putExtra("muted", call.argument<Boolean>("muted") ?: false)
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "setMemberVolume" -> {
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_COMMAND
                            putExtra("command", "setMemberVolume")
                            putExtra("ip",     call.argument<String>("ip"))
                            putExtra("volume",
                                call.argument<Double>("volume")?.toFloat() ?: 1.0f)
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "stopForegroundService" -> {
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "setNoiseLevel" -> {
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_COMMAND
                            putExtra("command", "setNoiseLevel")
                            putExtra("level", call.argument<Int>("level") ?: 1)
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "setMemberWifiDirectAddress" -> {
                        // Flutter envía la MAC WiFi Direct asociada a
                        // una IP de sala, para poder forzar reconexión
                        // si la señal se pierde por completo.
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_COMMAND
                            putExtra("command", "setMemberWifiDirectAddress")
                            putExtra("ip",      call.argument<String>("ip"))
                            putExtra("address", call.argument<String>("address"))
                        }
                        startService(intent)
                        result.success(null)
                    }
                    // Bluetooth y altavoz — se mantienen para la UI
                    "enableBluetooth" -> { enableBluetooth(); result.success(null) }
                    "disableBluetooth" -> { disableBluetooth(); result.success(null) }
                    "enableSpeaker" -> { enableSpeaker(); result.success(null) }
                    "disableSpeaker" -> { disableSpeaker(); result.success(null) }
                    "isBluetoothConnected" ->
                        result.success(isBluetoothHeadsetConnected())
                    else -> result.notImplemented()
                }
            }

        // ── EventChannel — sala ────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger,
            CallForegroundService.EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    EventBus.setSink(sink)
                }
                override fun onCancel(args: Any?) {
                    EventBus.setSink(null)
                }
            })

        // ── WiFi Direct ────────────────────────────────
        wifiDirect = WifiDirectService(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL))
        wifiDirect.initialize()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_DIRECT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "discoverPeers"       -> wifiDirect.discoverPeers(result)
                    "stopDiscovery"       -> wifiDirect.stopDiscovery(result)
                    "connect"             -> {
                        val address = call.argument<String>("address") ?: ""
                        wifiDirect.connect(address, result)
                    }
                    "disconnect"          -> wifiDirect.disconnect(result)
                    "createGroup"         -> wifiDirect.createGroup(result)
                    "removeGroup"         -> wifiDirect.removeGroup(result)
                    "requestGroupInfo"    -> wifiDirect.requestGroupInfo(result)
                    "requestConnectedPeers" -> wifiDirect.requestConnectedPeers(result)
                    "createGroupAndWait"  -> wifiDirect.createGroupAndWait(result)
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_DIRECT_EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    wifiDirect.setEventSink(sink)
                }
                override fun onCancel(args: Any?) {
                    wifiDirect.setEventSink(null)
                }
            })
    }

    // ── Bluetooth ──────────────────────────────────────
    private fun isBluetoothHeadsetConnected(): Boolean {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return false
        return adapter.isEnabled &&
                bluetoothHeadset?.connectedDevices?.isNotEmpty() == true
    }

    private fun enableBluetooth() {
        if (isBluetoothHeadsetConnected()) {
            audioManager?.isSpeakerphoneOn  = false
            audioManager?.isBluetoothScoOn  = true
            audioManager?.startBluetoothSco()
            isBtActive = true
        }
    }

    private fun disableBluetooth() {
        audioManager?.isBluetoothScoOn  = false
        audioManager?.stopBluetoothSco()
        audioManager?.isSpeakerphoneOn  = true
        isBtActive = false
    }

    private fun enableSpeaker() {
        if (isBtActive) {
            audioManager?.isBluetoothScoOn  = false
            audioManager?.stopBluetoothSco()
            isBtActive = false
        }
        audioManager?.isSpeakerphoneOn = true
    }

    private fun disableSpeaker() {
        audioManager?.isSpeakerphoneOn = false
    }

    // ── Helpers ────────────────────────────────────────
    private fun startForegroundServiceCompat(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun sendCommandToService(command: String) {
        val intent = Intent(this, CallForegroundService::class.java).apply {
            action = CallForegroundService.ACTION_COMMAND
            putExtra("command", command)
        }
        startService(intent)
    }

    override fun onDestroy() {
        super.onDestroy()
        wifiDirect.destroy()
    }
}
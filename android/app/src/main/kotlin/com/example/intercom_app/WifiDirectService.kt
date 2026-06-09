package com.example.intercom_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.WifiP2pConfig
import android.net.wifi.p2p.WifiP2pDevice
import android.net.wifi.p2p.WifiP2pManager
import android.net.wifi.p2p.WifiP2pManager.ActionListener
import android.net.wifi.p2p.WifiP2pManager.Channel
import android.os.Build
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class WifiDirectService(
    private val context: Context,
    private val methodChannel: MethodChannel,
) {
    private val manager: WifiP2pManager =
        context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
    private lateinit var channel: Channel

    private var eventSink: EventChannel.EventSink? = null
    private val peers = mutableListOf<WifiP2pDevice>()
    private var isGroupOwner = false
    private var groupOwnerAddress = ""

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    if (state != WifiP2pManager.WIFI_P2P_STATE_ENABLED) {
                        sendEvent("wifiDirectDisabled", null)
                    }
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    manager.requestPeers(channel) { peerList ->
                        peers.clear()
                        peers.addAll(peerList.deviceList)
                        val list = peers.map {
                            mapOf(
                                "name" to it.deviceName,
                                "address" to it.deviceAddress,
                                "status" to it.status
                            )
                        }
                        sendEvent("peersChanged", list)
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    @Suppress("DEPRECATION")
                    val networkInfo: android.net.NetworkInfo? =
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_NETWORK_INFO)

                    if (networkInfo?.isConnected == true) {
                        manager.requestConnectionInfo(channel) { info ->
                            isGroupOwner = info.isGroupOwner
                            groupOwnerAddress = info.groupOwnerAddress?.hostAddress ?: ""
                            sendEvent(
                                "connected", mapOf(
                                    "isGroupOwner" to isGroupOwner,
                                    "groupOwnerAddress" to groupOwnerAddress
                                )
                            )
                        }
                    } else {
                        sendEvent("disconnected", null)
                    }
                }
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    @Suppress("DEPRECATION")
                    val device: WifiP2pDevice? =
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE)
                    device?.let {
                        sendEvent("thisDeviceChanged", mapOf("name" to it.deviceName))
                    }
                }
            }
        }
    }

    fun initialize() {
        channel = manager.initialize(context, context.mainLooper, null)
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        context.registerReceiver(receiver, filter)
    }

    fun discoverPeers(result: MethodChannel.Result) {
        manager.discoverPeers(channel, object : ActionListener {
            override fun onSuccess() { result.success(null) }
            override fun onFailure(reason: Int) {
                result.error("DISCOVER_FAILED", "Error: $reason", null)
            }
        })
    }

    fun stopDiscovery(result: MethodChannel.Result) {
        manager.stopPeerDiscovery(channel, object : ActionListener {
            override fun onSuccess() { result.success(null) }
            override fun onFailure(reason: Int) { result.success(null) }
        })
    }

    fun connect(deviceAddress: String, result: MethodChannel.Result) {
        val config = WifiP2pConfig().apply { this.deviceAddress = deviceAddress }
        manager.connect(channel, config, object : ActionListener {
            override fun onSuccess() { result.success(null) }
            override fun onFailure(reason: Int) {
                result.error("CONNECT_FAILED", "Error: $reason", null)
            }
        })
    }

    fun disconnect(result: MethodChannel.Result) {
        manager.removeGroup(channel, object : ActionListener {
            override fun onSuccess() { result.success(null) }
            override fun onFailure(reason: Int) { result.success(null) }
        })
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    private fun sendEvent(type: String, data: Any?) {
        context.mainLooper.let {
            android.os.Handler(it).post {
                eventSink?.success(mapOf("type" to type, "data" to data))
            }
        }
    }

    fun destroy() {
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {}
        manager.removeGroup(channel, null)
    }
}
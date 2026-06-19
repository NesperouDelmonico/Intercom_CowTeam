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
            android.util.Log.d("WifiDirectService", "WIFI_P2P_PEERS_CHANGED_ACTION recibido")
            manager.requestPeers(channel) { peerList ->
              android.util.Log.d("WifiDirectService", "requestPeers callback: ${peerList.deviceList.size} dispositivos")
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
                    if (info.isGroupOwner && onGroupReady != null) {
                        onGroupReady?.invoke(groupOwnerAddress)
                    }

                    // Obtener las direcciones MAC de los dispositivos
                    // remotos del grupo, para que ambos lados (GO y
                    // cliente) sepan exactamente con quién se conectaron.
                    manager.requestGroupInfo(channel) { group ->
                        val remoteAddresses = mutableListOf<String>()
                        if (group != null) {
                            if (info.isGroupOwner) {
                                // Soy GO: los remotos son todos los clientes
                                remoteAddresses.addAll(
                                    group.clientList.map { it.deviceAddress }
                                )
                            } else {
                                // Soy cliente: el remoto es el GO
                                group.owner?.deviceAddress?.let {
                                    remoteAddresses.add(it)
                                }
                            }
                        }
                        android.util.Log.d("WifiDirectService",
                            "connected isGroupOwner=$isGroupOwner remoteAddresses=$remoteAddresses")
                        sendEvent("connected", mapOf(
                            "isGroupOwner" to isGroupOwner,
                            "groupOwnerAddress" to groupOwnerAddress,
                            "remoteAddresses" to remoteAddresses
                        ))
                    }
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
        android.util.Log.d("WifiDirectService", "discoverPeers() llamado")
        manager.discoverPeers(channel, object : ActionListener {
            override fun onSuccess() {
                android.util.Log.d("WifiDirectService", "discoverPeers onSuccess")
                result.success(null)
            }
            override fun onFailure(reason: Int) {
                android.util.Log.d("WifiDirectService", "discoverPeers onFailure reason=$reason")
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

    fun createGroup(result: MethodChannel.Result) {
    manager.createGroup(channel, object : ActionListener {
        override fun onSuccess() { result.success(null) }
        override fun onFailure(reason: Int) {
            result.error("CREATE_GROUP_FAILED", "Error: $reason", null)
        }
    })
}

fun removeGroup(result: MethodChannel.Result) {
    manager.removeGroup(channel, object : ActionListener {
        override fun onSuccess() { result.success(null) }
        override fun onFailure(reason: Int) { result.success(null) }
    })
}

fun requestGroupInfo(result: MethodChannel.Result) {
    manager.requestGroupInfo(channel) { group ->
        if (group == null) {
            result.success(null)
            return@requestGroupInfo
        }
        result.success(mapOf(
            "networkName" to group.networkName,
            "passphrase" to group.passphrase,
            "isGroupOwner" to true,
            "ownerAddress" to "192.168.49.1"
        ))
    }
}

    fun requestConnectedPeers(result: MethodChannel.Result) {
        manager.requestConnectionInfo(channel) { info ->
            if (info == null || !info.groupFormed) {
                result.success(emptyList<Map<String, String>>())
                return@requestConnectionInfo
            }

            if (info.isGroupOwner) {
                // Soy GO — pedir lista de clientes
                manager.requestGroupInfo(channel) { group ->
                    if (group == null) {
                        result.success(emptyList<Map<String, String>>())
                        return@requestGroupInfo
                    }
                    val clients = group.clientList.map { device ->
                        mapOf(
                            "name" to device.deviceName,
                            "address" to device.deviceAddress,
                        )
                    }
                    result.success(clients)
                }
            } else {
                // Soy cliente — el GO es mi único peer conectado
                val goAddress = info.groupOwnerAddress?.hostAddress ?: ""
                // Buscar el nombre del GO en la lista de peers
                val goName = peers.find { peer ->
                    // El GO puede estar en la lista con status 0 (conectado)
                    peer.status == 0
                }?.deviceName ?: "Group Owner"

                result.success(listOf(
                    mapOf(
                        "name" to goName,
                        "address" to goAddress,
                    )
                ))
            }
        }
    }

    private var onGroupReady: ((String) -> Unit)? = null

   fun createGroupAndWait(result: MethodChannel.Result) {
    // Primero remover cualquier grupo existente
    manager.removeGroup(channel, object : ActionListener {
        override fun onSuccess() { doCreateGroup(result) }
        override fun onFailure(reason: Int) { doCreateGroup(result) }
    })
}

    private fun doCreateGroup(result: MethodChannel.Result) {
        manager.createGroup(channel, object : ActionListener {
            override fun onSuccess() {
                onGroupReady = { ownerIp ->
                    result.success(ownerIp)
                    onGroupReady = null
                }
                // Timeout de seguridad — si en 10s no llega el evento, resolver igual
                android.os.Handler(context.mainLooper).postDelayed({
                    if (onGroupReady != null) {
                        onGroupReady = null
                        result.success("192.168.49.1")
                    }
                }, 10000)
            }
            override fun onFailure(reason: Int) {
                // Si falla (por ejemplo ya hay grupo), resolver con GO IP
                result.success("192.168.49.1")
            }
        })
    }
}
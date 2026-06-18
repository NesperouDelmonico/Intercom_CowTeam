package com.example.intercom_app

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors
import java.net.NetworkInterface

class UdpEngine {

    companion object {
        const val AUDIO_PORT    = 5560
        const val SIGNAL_PORT   = 5561
        const val ANNOUNCE_PORT = 5562
    }

    private var audioSocket:    DatagramSocket? = null
    private var signalSocket:   DatagramSocket? = null
    private var announceSocket: DatagramSocket? = null

    private var audioReceiveThread:    Thread? = null
    private var signalReceiveThread:   Thread? = null
    private var announceReceiveThread: Thread? = null

    // Executor como var para poder recrearlo
    private var sendExecutor = Executors.newSingleThreadExecutor()

    private var isRunning = false

    var onAudioReceived:    ((ByteArray, String) -> Unit)? = null
    var onSignalReceived:   ((String, String) -> Unit)? = null
    var onAnnounceReceived: ((String, String) -> Unit)? = null

    // ── INICIAR ────────────────────────────────────────
    fun start() {
        if (isRunning) return
        isRunning = true

        // Recrear executor si fue cerrado
        if (sendExecutor.isShutdown) {
            sendExecutor = Executors.newSingleThreadExecutor()
        }

        try { audioSocket    = DatagramSocket(AUDIO_PORT)    } catch (_: Exception) {}
        try { signalSocket   = DatagramSocket(SIGNAL_PORT)   } catch (_: Exception) {}
        try {
                announceSocket = DatagramSocket(ANNOUNCE_PORT)
                announceSocket?.broadcast = true
            } catch (_: Exception) {}

        startAudioReceiver()
        startSignalReceiver()
        startAnnounceReceiver()
    }

    // ── RECEPTORES ─────────────────────────────────────
    private fun startAudioReceiver() {
        val buffer = ByteArray(2048)
        audioReceiveThread = Thread {
            while (isRunning) {
                try {
                    val packet = DatagramPacket(buffer, buffer.size)
                    audioSocket?.receive(packet) ?: break
                    val data   = packet.data.copyOf(packet.length)
                    val fromIp = packet.address.hostAddress ?: continue
                    onAudioReceived?.invoke(data, fromIp)
                } catch (_: Exception) {
                    if (!isRunning) break
                }
            }
        }
        audioReceiveThread?.priority = Thread.MAX_PRIORITY
        audioReceiveThread?.start()
    }

    private fun startSignalReceiver() {
        val buffer = ByteArray(8192)
        signalReceiveThread = Thread {
            while (isRunning) {
                try {
                    val packet = DatagramPacket(buffer, buffer.size)
                    signalSocket?.receive(packet) ?: break
                    val msg    = String(packet.data, 0, packet.length)
                    val fromIp = packet.address.hostAddress ?: continue
                    onSignalReceived?.invoke(msg, fromIp)
                } catch (_: Exception) {
                    if (!isRunning) break
                }
            }
        }
        signalReceiveThread?.start()
    }

    private fun startAnnounceReceiver() {
        val buffer = ByteArray(8192)
        announceReceiveThread = Thread {
            while (isRunning) {
                try {
                    val packet = DatagramPacket(buffer, buffer.size)
                    announceSocket?.receive(packet) ?: break
                    val msg    = String(packet.data, 0, packet.length)
                    val fromIp = packet.address.hostAddress ?: continue
                    onAnnounceReceived?.invoke(msg, fromIp)
                } catch (_: Exception) {
                    if (!isRunning) break
                }
            }
        }
        announceReceiveThread?.start()
    }

    // ── ENVÍO ──────────────────────────────────────────
    private fun safeExecute(block: () -> Unit) {
        if (!sendExecutor.isShutdown) {
            try { sendExecutor.execute(block) } catch (_: Exception) {}
        }
    }

    fun sendAudio(data: ByteArray, targetIps: List<String>) {
        safeExecute {
            for (ip in targetIps) {
                try {
                    val address = InetAddress.getByName(ip)
                    val packet  = DatagramPacket(data, data.size, address, AUDIO_PORT)
                    audioSocket?.send(packet)
                } catch (_: Exception) {}
            }
        }
    }

    fun sendSignal(msg: String, targetIp: String) {
        safeExecute {
            try {
                val data    = msg.toByteArray()
                val address = InetAddress.getByName(targetIp)
                val packet  = DatagramPacket(data, data.size, address, SIGNAL_PORT)
                signalSocket?.send(packet)
            } catch (_: Exception) {}
        }
    }

    fun broadcastSignal(msg: String, memberIps: List<String>) {
        safeExecute {
            val data = msg.toByteArray()
            for (ip in memberIps) {
                try {
                    val address = InetAddress.getByName(ip)
                    val packet  = DatagramPacket(data, data.size, address, SIGNAL_PORT)
                    signalSocket?.send(packet)
                } catch (_: Exception) {}
            }
            try {
                val broadcast = InetAddress.getByName("192.168.49.255")
                val packet    = DatagramPacket(data, data.size, broadcast, SIGNAL_PORT)
                signalSocket?.send(packet)
            } catch (_: Exception) {}
        }
    }

    fun sendAnnounce(msg: String) {
        safeExecute {
            val data = msg.toByteArray()
            try {
                val wd = InetAddress.getByName("192.168.49.255")
                announceSocket?.send(DatagramPacket(data, data.size, wd, ANNOUNCE_PORT))
            } catch (_: Exception) {}
            try {
                val bc = InetAddress.getByName("255.255.255.255")
                announceSocket?.send(DatagramPacket(data, data.size, bc, ANNOUNCE_PORT))
            } catch (_: Exception) {}
        }
    }

    fun sendAnnounceTo(msg: String, targetIp: String) {
        safeExecute {
            try {
                val data    = msg.toByteArray()
                val address = InetAddress.getByName(targetIp)
                val packet  = DatagramPacket(data, data.size, address, ANNOUNCE_PORT)
                announceSocket?.send(packet)
            } catch (_: Exception) {}
        }
    }

    // ── DETENER ────────────────────────────────────────
    fun stop() {
        isRunning = false
        audioSocket?.close()
        signalSocket?.close()
        announceSocket?.close()
        audioSocket    = null
        signalSocket   = null
        announceSocket = null
        audioReceiveThread?.interrupt()
        signalReceiveThread?.interrupt()
        announceReceiveThread?.interrupt()
        audioReceiveThread    = null
        signalReceiveThread   = null
        announceReceiveThread = null
        if (!sendExecutor.isShutdown) sendExecutor.shutdown()
    }
}
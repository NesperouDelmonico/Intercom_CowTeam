package com.example.intercom_app

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors

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

    var onAudioReceived:    ((ByteArray, String, Long) -> Unit)? = null
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
        // Formato del paquete de audio:
        // [0..7]  = timestamp Long (8 bytes, big-endian)
        // [8..]   = datos PCM16
        val buffer = ByteArray(2048 + 8)
        audioReceiveThread = Thread {
            while (isRunning) {
                try {
                    val packet = DatagramPacket(buffer, buffer.size)
                    audioSocket?.receive(packet) ?: break
                    val raw    = packet.data.copyOf(packet.length)
                    val fromIp = packet.address.hostAddress ?: continue

                    if (raw.size < 8) continue

                    // Extraer timestamp de los primeros 8 bytes
                    var ts = 0L
                    for (b in 0..7) ts = (ts shl 8) or (raw[b].toLong() and 0xFF)

                    val data = raw.copyOfRange(8, raw.size)
                    onAudioReceived?.invoke(data, fromIp, ts)
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
        // Prefijar el timestamp de captura (8 bytes big-endian)
        // para que el MixerEngine pueda sincronizar fuentes múltiples.
        val ts     = System.currentTimeMillis()
        val header = ByteArray(8)
        for (b in 7 downTo 0) {
            header[b] = (ts shr ((7 - b) * 8)).toByte()
        }
        val packet = header + data

        safeExecute {
            for (ip in targetIps) {
                try {
                    val address = InetAddress.getByName(ip)
                    val dgram   = DatagramPacket(packet, packet.size, address, AUDIO_PORT)
                    audioSocket?.send(dgram)
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
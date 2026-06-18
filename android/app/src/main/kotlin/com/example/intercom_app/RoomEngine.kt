package com.example.intercom_app

import android.os.Handler
import android.os.Looper
import java.util.concurrent.ConcurrentHashMap
import java.util.Timer
import java.util.TimerTask
import kotlin.math.sqrt

data class RoomMemberNative(
    val name: String,
    val ip: String,
    var avatarBase64: String? = null,
    var isMuted: Boolean = false,
    var volume: Float = 1.0f,
    var speakingLevel: Float = 0.0f,
    var isOnline: Boolean = true,
    var lastSeen: Long = System.currentTimeMillis()
)

class RoomEngine(
    private val udp: UdpEngine,
    private val audio: AudioEngine,
    private val sound: SoundEngine,
) {
    companion object {
        const val MEMBER_TIMEOUT_MS  = 2_000L
        const val HEARTBEAT_MS       = 400L
        const val ANNOUNCE_MS        = 350L
        const val RECONNECT_DELAY_MS = 100L
    }

    private val members = ConcurrentHashMap<String, RoomMemberNative>()
    private val knownMembers: MutableSet<String> = ConcurrentHashMap.newKeySet()
    private val mainHandler = Handler(Looper.getMainLooper())
    

    private var myIp      = ""
    private var myName    = ""
    private var myAvatar  = ""
    private var roomCode  = ""
    private var isRunning = false

    private var heartbeatTimer: Timer? = null
    private var announceTimer:  Timer? = null
    private var timeoutTimer:   Timer? = null

    // ── INICIAR SALA ───────────────────────────────────
    fun start(
        myIp: String,
        myName: String,
        myAvatar: String,
        roomCode: String,
    ) {
        this.myIp      = myIp
        this.myName    = myName
        this.myAvatar  = myAvatar
        this.roomCode  = roomCode
        this.isRunning = true

        members[myIp] = RoomMemberNative(
            name         = myName,
            ip           = myIp,
            avatarBase64 = myAvatar.ifEmpty { null },
            isOnline     = true,
            lastSeen     = System.currentTimeMillis()
        )

        knownMembers.add(myIp)
        setupUdpCallbacks()
        startHeartbeat()
        startAnnounce()
        startTimeoutChecker()

        audio.onAudioCaptured = { chunk ->
            val targets = members.entries
                .filter { it.key != myIp && it.value.isOnline && !it.value.isMuted }
                .map { it.key }
            if (targets.isNotEmpty()) udp.sendAudio(chunk, targets)
        }
        audio.startCapture()

        // Notificar inmediatamente con el miembro propio
        notifyMembersChanged()
    }

    // ── RECEPTORES UDP ─────────────────────────────────
    private fun setupUdpCallbacks() {
        udp.onAudioReceived = { data, fromIp ->
            val member = members[fromIp]
            if (member != null && !member.isMuted) {
                val level = calculateRms(data)
                member.speakingLevel = level
                member.lastSeen      = System.currentTimeMillis()
                member.isOnline      = true
                audio.playChunk(data, member.volume)
                EventBus.send("speakingLevel",
                    mapOf("ip" to fromIp, "level" to level))
            }
        }

        udp.onSignalReceived = { msg, fromIp ->
            if (fromIp != myIp) handleSignal(msg, fromIp)
        }

        udp.onAnnounceReceived = { msg, fromIp ->
            if (fromIp != myIp) handleAnnounce(msg, fromIp)
        }
    }

    // ── SEÑALIZACIÓN ───────────────────────────────────
    private fun handleSignal(msg: String, fromIp: String) {
        when {
            msg.startsWith("LEAVE:") -> handleLeave(fromIp)
            msg.startsWith("MUTED:") -> handleMuted(msg)
            msg.startsWith("WHO:")   -> sendAnnounceTo(fromIp)
        }
    }

    private fun handleLeave(fromIp: String) {
        val member = members[fromIp] ?: return
        member.isOnline = false  // ← marcar offline en lugar de remover
        sound.playLeave()
        EventBus.send("memberLeft", mapOf("name" to member.name, "ip" to member.ip))
        notifyMembersChanged()
    }

    private fun handleMuted(msg: String) {
        val parts = msg.split(":")
        if (parts.size < 3) return
        val ip    = parts[1]
        val muted = parts[2] == "1"
        members[ip]?.isMuted = muted
        notifyMembersChanged()
    }

    // ── ANNOUNCE ───────────────────────────────────────
    private fun handleAnnounce(msg: String, fromIp: String) {
        if (!msg.startsWith("ANNOUNCE:")) return
        val parts = msg.split(":")
        if (parts.size < 5) return

        val code   = parts[1]
        val ip     = parts[2]
        val name   = parts[3]
        val avatar = parts[4]
        val knownMembers = if (parts.size > 5 && parts[5].isNotEmpty())
            parts[5].split(",") else emptyList()

        if (code != roomCode) return

        val isNew      = !members.containsKey(ip)
        val wasOffline = members[ip]?.isOnline == false

        members[ip] = RoomMemberNative(
            name         = name,
            ip           = ip,
            avatarBase64 = avatar.ifEmpty { null },
            isOnline     = true,
            lastSeen     = System.currentTimeMillis()
        )

        if (isNew) {
            members[ip] = RoomMemberNative(
                name         = name,
                ip           = ip,
                avatarBase64 = avatar.ifEmpty { null },
                isOnline     = true,
                lastSeen     = System.currentTimeMillis()
            )
            // isNew ya garantiza que es genuinamente nuevo
            sound.playJoin()
            EventBus.send("memberJoined", mapOf("name" to name, "ip" to ip))
            notifyMembersChanged()
        } else {
            members[ip]?.apply {
                lastSeen = System.currentTimeMillis()
                isOnline = true
                if (avatarBase64 == null && avatar.isNotEmpty()) {
                    avatarBase64 = avatar
                }
            }
            if (wasOffline) {
                // Reconexión — sí reproducir join
                sound.playJoin()
                EventBus.send("memberJoined", mapOf("name" to name, "ip" to ip))
                notifyMembersChanged()
            }
        }

        // Descubrir miembros que el otro conoce y nosotros no
        for (memberIp in knownMembers) {
            if (memberIp.isNotEmpty() && memberIp != myIp &&
                !members.containsKey(memberIp)) {
                mainHandler.postDelayed({
                    sendAnnounceTo(memberIp)
                }, RECONNECT_DELAY_MS)
            }
        }

        // Responder con nuestro propio ANNOUNCE
        sendAnnounceTo(ip)
    }

    private fun buildAnnounceMsg(): String {
        val knownIps = members.keys.filter { it != myIp }.joinToString(",")
        return "ANNOUNCE:$roomCode:$myIp:$myName:$myAvatar:$knownIps"
    }

    private fun sendAnnounceTo(targetIp: String) {
        udp.sendAnnounceTo(buildAnnounceMsg(), targetIp)
    }

    private fun sendAnnounceBroadcast() {
        val msg = buildAnnounceMsg()
        udp.sendAnnounce(msg)
        for (ip in members.keys) {
            if (ip != myIp) udp.sendAnnounceTo(msg, ip)
        }
    }

    // ── TIMERS ─────────────────────────────────────────
    private fun startHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = Timer()
        heartbeatTimer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                if (!isRunning) return
                sendAnnounceBroadcast()
            }
        }, 0L, HEARTBEAT_MS)
    }

    private fun startAnnounce() {
        announceTimer?.cancel()
        announceTimer = Timer()
        announceTimer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                if (!isRunning) return
                udp.sendAnnounce(buildAnnounceMsg())
            }
        }, 0L, ANNOUNCE_MS)
    }

    private fun startTimeoutChecker() {
        timeoutTimer?.cancel()
        timeoutTimer = Timer()
        timeoutTimer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                if (!isRunning) return
                val now     = System.currentTimeMillis()
                var changed = false
                for (member in members.values) {
                    if (member.ip == myIp) continue
                    val elapsed = now - member.lastSeen
                    if (elapsed > MEMBER_TIMEOUT_MS && member.isOnline) {
                        member.isOnline = false
                        changed = true
                        EventBus.send("memberLeft",
                            mapOf("name" to member.name, "ip" to member.ip))
                            sound.playLeave()
                    }
                }
                if (changed) notifyMembersChanged()

                // Notificar estado de conexión
                val onlineCount = members.values.count { 
                    it.ip != myIp && it.isOnline 
                }
                val totalCount = members.values.count { it.ip != myIp }
                if (totalCount > 0 && onlineCount == 0) {
                    EventBus.send("connectionLost", null)
                } else if (onlineCount > 0) {
                    EventBus.send("connectionRestored", null)
                }
            }
        }, 1000L, 500L)
    }

    // ── CONTROLES ──────────────────────────────────────
    fun setMemberMuted(ip: String, muted: Boolean) {
        members[ip]?.isMuted = muted
        val msg = "MUTED:$ip:${if (muted) "1" else "0"}"
        udp.broadcastSignal(msg, members.keys.filter { it != myIp })
        notifyMembersChanged()
    }

    fun setMemberVolume(ip: String, volume: Float) {
        members[ip]?.volume = volume
        notifyMembersChanged()
    }

    fun setMicGain(gain: Float) {
        audio.micGain = gain
    }

    fun setVox(enabled: Boolean, threshold: Double) {
        audio.voxEnabled   = enabled
        audio.voxThreshold = threshold
    }

    fun setMuted(muted: Boolean) {
        audio.onAudioCaptured = if (muted) {
            { _ -> }
        } else {
            { chunk ->
                val targets = members.entries
                    .filter { it.key != myIp &&
                        it.value.isOnline &&
                        !it.value.isMuted }
                    .map { it.key }
                if (targets.isNotEmpty()) udp.sendAudio(chunk, targets)
            }
        }
    }

    // ── UTILIDADES ─────────────────────────────────────
    private fun calculateRms(data: ByteArray): Float {
        var sum = 0.0
        var i = 0
        while (i < data.size - 1) {
            val s = (data[i].toInt() and 0xFF) or
                    ((data[i + 1].toInt() and 0xFF) shl 8)
            val signed = if (s > 32767) s - 65536 else s
            sum += signed * signed
            i += 2
        }
        val rms = sqrt(sum / (data.size / 2))
        return (rms / 8000.0).toFloat().coerceIn(0f, 1f)
    }

    private fun notifyMembersChanged() {
        val list = members.values.map { m ->
            mapOf<String, Any?>(
                "name"          to m.name,
                "ip"            to m.ip,
                "avatarBase64"  to m.avatarBase64,
                "isMuted"       to m.isMuted,
                "volume"        to m.volume.toDouble(),
                "speakingLevel" to m.speakingLevel.toDouble(),
                "isOnline"      to m.isOnline,
            )
        }
        EventBus.send("membersChanged", list)
    }

    fun setNoiseLevel(level: Int) {
        audio.setNoiseLevel(level)
    }

    // ── SALIR ──────────────────────────────────────────
    fun leave() {
        isRunning = false
        val targets = members.keys.filter { it != myIp }
        udp.broadcastSignal("LEAVE:$myIp", targets)
        heartbeatTimer?.cancel()
        announceTimer?.cancel()
        timeoutTimer?.cancel()
        audio.stopCapture()
        members.clear()
        knownMembers.clear()
    }
}
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
    var lastSeen: Long = System.currentTimeMillis(),
    // ── Histeresis de notificaciones ────────────────
    // offlineSince: momento en que dejamos de recibir señal de este
    // miembro (null mientras está online o ya fue confirmado/notificado)
    var offlineSince: Long? = null,
    // leftConfirmed: true si ya se notificó realmente la salida de
    // este miembro para el período offline actual.
    var leftConfirmed: Boolean = false,
    // ignoreAnnouncesUntil: tras un LEAVE explícito, ignoramos
    // cualquier ANNOUNCE residual de esta IP durante una ventana
    // corta, para evitar el rebote entrada/salida por paquetes
    // que ya estaban en tránsito cuando se cerró la conexión.
    var ignoreAnnouncesUntil: Long = 0L,
    // wifiDirectAddress: dirección MAC WiFi Direct de este miembro,
    // si se conoce. Se usa para el historial de reconexión
    // automática — al volver al rango, forzar conexión con
    // cualquiera de los miembros conocidos de la última sala.
    var wifiDirectAddress: String? = null,
    // ── Confirmación de reconexión real ─────────────
    // Tras una salida CONFIRMADA (leftConfirmed=true), un solo
    // ANNOUNCE aislado puede ser un paquete residual fantasma, no
    // una reconexión real. Exigimos 2 ANNOUNCEs consecutivos en
    // menos de RECONNECT_CONFIRM_WINDOW_MS antes de creer que
    // el miembro realmente volvió.
    var pendingReconnectSince: Long? = null,
)

class RoomEngine(
    private val udp: UdpEngine,
    private val audio: AudioEngine,
    private val sound: SoundEngine,
) {
    companion object {
        const val MEMBER_TIMEOUT_MS  = 3_000L  // tolera ~3 anuncios perdidos
        const val ANNOUNCE_MS        = 1_000L  // 1 anuncio por segundo
        const val RECONNECT_DELAY_MS = 200L
        // Tiempo de gracia tras detectar pérdida de señal antes de
        // confirmar la salida real (regla acordada: 5 segundos).
        const val LEAVE_CONFIRM_MS   = 5_000L
        // Tras un LEAVE explícito, ignorar ANNOUNCEs residuales de
        // esa IP durante esta ventana (evita rebote entrada/salida).
        const val IGNORE_AFTER_LEAVE_MS = 3_000L
        // Tras una salida CONFIRMADA por timeout, ventana máxima
        // entre dos ANNOUNCEs consecutivos para considerar que es
        // una reconexión real y no un paquete fantasma aislado.
        const val RECONNECT_CONFIRM_WINDOW_MS = 1_500L
        // Al unirse uno mismo a una sala con miembros preexistentes,
        // no mostrar texto de "X se unió" por esos miembros durante
        // esta ventana — solo es ruido de bienvenida, no información
        // nueva para quien recién entra.
        const val JOIN_GRACE_MS = 1_500L
        // Si el banner "Reconectando" lleva activo más de este tiempo,
        // pedimos a Flutter que intente forzar la reconexión WiFi
        // Direct con algún miembro conocido de la sala.
        const val FORCE_RECONNECT_AFTER_MS = 8_000L
        // Tiempo que debe mantenerse estable la condición "recuperado"
        // antes de apagar el banner — filtra parpadeos momentáneos
        // que de otro modo reiniciarían el contador de FORCE_RECONNECT.
        const val BANNER_OFF_STABILITY_MS = 2_000L
    }

    private val members = ConcurrentHashMap<String, RoomMemberNative>()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var myIp      = ""
    private var myName    = ""
    private var myAvatar  = ""
    private var roomCode  = ""
    private var isRunning = false

    // Para distinguir "estoy solo porque acabo de crear la sala" de
    // "estaba acompañado y de repente quedé solo" (señal de reconexión).
    private var everHadOtherMembers = false
    // Evita evaluar el banner de reconexión tras un leave() voluntario.
    private var voluntaryLeaveInProgress = false
    // true mientras estamos mostrando el banner "Reconectando" — se usa
    // para saber cuándo reproducir el sonido de "volví a conectar".
    private var isReconnecting = false
    // Momento en que se activó el banner — si pasa demasiado tiempo,
    // pedimos a Flutter forzar una reconexión WiFi Direct.
    private var reconnectingSince: Long? = null
    // true una vez que ya pedimos la reconexión forzada para este
    // período de banner — evita pedirla repetidamente cada segundo.
    private var forceReconnectRequested = false
    // Momento en que detectamos una posible recuperación (banner
    // podría apagarse) — null mientras no hay recuperación pendiente
    // de confirmar. Se usa para exigir estabilidad antes de apagar.
    private var recoveryDetectedAt: Long? = null

    private var announceTimer: Timer? = null
    private var timeoutTimer:  Timer? = null
    // Momento en que este dispositivo se unió a la sala — se usa
    // para suprimir notificaciones de "bienvenida" sobre miembros
    // que ya estaban presentes antes de que nosotros llegáramos.
    private var joinedAt: Long = 0L

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
        this.joinedAt  = System.currentTimeMillis()

        members[myIp] = RoomMemberNative(
            name         = myName,
            ip           = myIp,
            avatarBase64 = myAvatar.ifEmpty { null },
            isOnline     = true,
            lastSeen     = System.currentTimeMillis()
        )

        // Caso "dueño crea la sala y está solo" — entrada genuina propia.
        sound.playJoin()
        EventBus.send("memberJoined", mapOf("name" to myName, "ip" to myIp, "isSelf" to true))

        setupUdpCallbacks()
        startAnnounce()
        startTimeoutChecker()

        audio.onAudioCaptured = { chunk ->
            val targets = members.entries
                .filter { it.key != myIp && it.value.isOnline && !it.value.isMuted }
                .map { it.key }
            if (targets.isNotEmpty()) udp.sendAudio(chunk, targets)
        }
        audio.startCapture()

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
            handleAnnounce(msg, fromIp)
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

    // ── CASO: Salida voluntaria (botón "Salir") ────────
    // Inmediata, sin período de gracia — es una acción intencional.
    // Idempotente: LEAVE duplicados (reenviados por confiabilidad UDP)
    // se ignoran silenciosamente una vez notificado.
    private fun handleLeave(fromIp: String) {
        val member = members[fromIp] ?: return
        if (member.leftConfirmed) return

        member.isOnline      = false
        member.offlineSince  = null
        member.leftConfirmed = true
        // Ignorar cualquier ANNOUNCE residual de esta IP durante los
        // próximos segundos — evita que paquetes ya en tránsito
        // generen un rebote entrada/salida tras el LEAVE explícito.
        member.ignoreAnnouncesUntil =
            System.currentTimeMillis() + IGNORE_AFTER_LEAVE_MS

        sound.playLeave()
        EventBus.send("memberLeft", mapOf("name" to member.name, "ip" to member.ip))
        notifyMembersChanged()
        checkReconnectionBanner()
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
        val knownIps = if (parts.size > 5 && parts[5].isNotEmpty())
            parts[5].split(",") else emptyList()

        if (code != roomCode) return
        if (ip == myIp) return

        val existing = members[ip]

        // Ignorar ANNOUNCEs residuales tras un LEAVE explícito reciente
        // de esta IP — evita el rebote entrada/salida por paquetes que
        // ya estaban en tránsito cuando se cerró la conexión.
        if (existing != null) {
            val now = System.currentTimeMillis()
            if (now < existing.ignoreAnnouncesUntil) return
        }

        val isNew      = existing == null
        val wasOffline = existing?.isOnline == false

        android.util.Log.d("RoomEngine",
            "ANNOUNCE ip=$ip isNew=$isNew wasOffline=$wasOffline " +
            "leftConfirmed=${existing?.leftConfirmed} " +
            "pendingReconnect=${existing?.pendingReconnectSince} " +
            "isOnline=${existing?.isOnline}")

        // ¿Estamos todavía dentro de la ventana de gracia de nuestra
        // propia entrada a la sala? Si es así, no se debe notificar
        // con texto la presencia de miembros que ya estaban aquí —
        // solo es ruido de bienvenida para quien recién llega.
        val withinOwnJoinGrace =
            (System.currentTimeMillis() - joinedAt) < JOIN_GRACE_MS

        if (isNew) {
            // ── CASO: Participante genuinamente nuevo ──────
            // A todos se les notifica (texto + sonido), salvo que
            // sea nuestra propia ventana de bienvenida (entonces
            // este "nuevo" miembro en realidad ya estaba en la sala
            // antes que nosotros — solo sonido, sin texto).
            members[ip] = RoomMemberNative(
                name         = name,
                ip           = ip,
                avatarBase64 = avatar.ifEmpty { null },
                isOnline     = true,
                lastSeen     = System.currentTimeMillis()
            )
            everHadOtherMembers = true
            if (withinOwnJoinGrace) {
                sound.playJoin()
                EventBus.send("memberJoined",
                    mapOf("name" to name, "ip" to ip, "isSelf" to true))
            } else {
                sound.playJoin()
                EventBus.send("memberJoined",
                    mapOf("name" to name, "ip" to ip, "isSelf" to false))
            }
            notifyMembersChanged()
        } else {
            if (wasOffline && existing!!.leftConfirmed) {
                // ── CASO: posible reconexión tras salida CONFIRMADA ──
                // No confiamos en un solo ANNOUNCE aislado (puede ser
                // un paquete fantasma residual de la desconexión). Se
                // exige un segundo ANNOUNCE dentro de una ventana
                // corta antes de aceptar la reconexión como real —
                // mientras tanto, NO se toca isOnline (la tarjeta
                // permanece oculta/offline, sin parpadeo).
                val now = System.currentTimeMillis()
                val pending = existing.pendingReconnectSince

                if (pending == null) {
                    // Primer ANNOUNCE tras la salida confirmada —
                    // solo lo registramos, sin marcar online todavía.
                    existing.pendingReconnectSince = now
                    existing.lastSeen = now
                    if (existing.avatarBase64 == null && avatar.isNotEmpty()) {
                        existing.avatarBase64 = avatar
                    }
                } else if (now - pending <= RECONNECT_CONFIRM_WINDOW_MS) {
                    // Segundo ANNOUNCE a tiempo — reconexión real.
                    existing.lastSeen = now
                    existing.isOnline = true
                    existing.offlineSince = null
                    existing.leftConfirmed = false
                    existing.pendingReconnectSince = null
                    if (existing.avatarBase64 == null && avatar.isNotEmpty()) {
                        existing.avatarBase64 = avatar
                    }
                    sound.playJoin()
                    EventBus.send("memberJoined",
                        mapOf("name" to name, "ip" to ip, "isSelf" to false))
                    notifyMembersChanged()
                } else {
                    // Pasó demasiado tiempo entre anuncios — era un
                    // paquete fantasma aislado. Reiniciamos el contador
                    // con este ANNOUNCE como nuevo "primer" intento.
                    existing.pendingReconnectSince = now
                    existing.lastSeen = now
                }
            } else {
                existing!!.lastSeen = System.currentTimeMillis()
                existing.isOnline = true
                if (existing.avatarBase64 == null && avatar.isNotEmpty()) {
                    existing.avatarBase64 = avatar
                }

                if (wasOffline) {
                    // ── CASO: Parpadeo dentro del período de gracia ──
                    // Nunca se confirmó la salida — silencio total.
                    existing.offlineSince = null
                    notifyMembersChanged()
                }
            }
        }

        for (memberIp in knownIps) {
            if (memberIp.isNotEmpty() && memberIp != myIp &&
                !members.containsKey(memberIp)) {
                mainHandler.postDelayed({
                    sendAnnounceTo(memberIp)
                }, RECONNECT_DELAY_MS)
            }
        }

        sendAnnounceTo(ip)
        checkReconnectionBanner()
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
    private fun startAnnounce() {
        announceTimer?.cancel()
        announceTimer = Timer()
        announceTimer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                if (!isRunning) return
                sendAnnounceBroadcast()
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

                    // Paso 1 — detectar pérdida de señal, sin notificar
                    // todavía (inicia el período de gracia de 5s).
                    val elapsed = now - member.lastSeen
                    if (elapsed > MEMBER_TIMEOUT_MS && member.isOnline) {
                        member.isOnline = false
                        member.offlineSince = now
                        changed = true
                    }

                    // Paso 2 — si pasó el período de gracia sin que
                    // reapareciera, confirmar la salida (única vez
                    // que se notifica realmente, regla acordada).
                    if (!member.isOnline && !member.leftConfirmed) {
                        val since = member.offlineSince
                        if (since != null && now - since >= LEAVE_CONFIRM_MS) {
                            member.leftConfirmed = true
                            sound.playLeave()
                            EventBus.send("memberLeft",
                                mapOf("name" to member.name, "ip" to member.ip))
                            changed = true
                        }
                    }
                }
                if (changed) notifyMembersChanged()
                checkReconnectionBanner()
            }
        }, 1000L, 1000L)
    }

    // ── BANNER "RECONECTANDO" ───────────────────────────
    // Regla acordada: el banner se dispara cuando la lista de
    // miembros pasa a contener solo al propio usuario, Y eso no
    // fue causado por un leave() voluntario propio.
    //
    // Para que el contador de "tiempo en banner" no se reinicie por
    // parpadeos momentáneos (un ANNOUNCE aislado que marca online por
    // un instante), exigimos que el estado "recuperado" se mantenga
    // estable por BANNER_OFF_STABILITY_MS antes de apagar el banner
    // y resetear reconnectingSince.
    private fun checkReconnectionBanner() {
        if (voluntaryLeaveInProgress) return

        val onlineOthers = members.values.count { it.ip != myIp && it.isOnline }
        val totalOthers  = members.values.count { it.ip != myIp }

        val shouldShowBanner = everHadOtherMembers && totalOthers > 0 && onlineOthers == 0

        if (shouldShowBanner && !isReconnecting) {
            isReconnecting = true
            reconnectingSince = System.currentTimeMillis()
            forceReconnectRequested = false
            recoveryDetectedAt = null
            EventBus.send("connectionLost", null)
            return
        }

        if (!shouldShowBanner && isReconnecting) {
            // Posible recuperación — no apagamos el banner todavía.
            // Solo lo confirmamos si esta condición se mantiene
            // estable por un breve margen (filtra parpadeos).
            val now = System.currentTimeMillis()
            if (recoveryDetectedAt == null) {
                recoveryDetectedAt = now
                return
            }
            if (now - recoveryDetectedAt!! < BANNER_OFF_STABILITY_MS) {
                return // todavía no es estable, esperar más
            }
            // Recuperación confirmada y estable — apagar banner.
            isReconnecting = false
            reconnectingSince = null
            forceReconnectRequested = false
            recoveryDetectedAt = null
            sound.playJoin()
            EventBus.send("connectionRestored", null)
            return
        }

        // Si volvemos a shouldShowBanner=true mientras estábamos
        // evaluando una posible recuperación, descartamos esa
        // recuperación — fue solo un parpadeo, el banner sigue activo
        // y el contador de tiempo NO se reinicia.
        if (shouldShowBanner && isReconnecting) {
            recoveryDetectedAt = null

            if (!forceReconnectRequested) {
                val since = reconnectingSince
                if (since != null &&
                    System.currentTimeMillis() - since >= FORCE_RECONNECT_AFTER_MS) {
                    forceReconnectRequested = true
                    val candidateAddresses = members.values
                        .filter { it.ip != myIp && it.wifiDirectAddress != null }
                        .map { it.wifiDirectAddress!! }
                    EventBus.send("forceReconnectWifiDirect",
                        mapOf("addresses" to candidateAddresses))
                }
            }
        }
    }

    // ── HISTORIAL WIFI DIRECT ───────────────────────────
    // Flutter conoce las MACs WiFi Direct asociadas a cada IP de sala
    // (vía WifiDirectService) y las envía aquí para poder forzar una
    // reconexión si la señal se pierde por completo.
    fun setMemberWifiDirectAddress(ip: String, address: String) {
        members[ip]?.wifiDirectAddress = address
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

    fun setNoiseLevel(level: Int) {
        audio.setNoiseLevel(level)
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

    // ── SALIR ──────────────────────────────────────────
    fun leave() {
        voluntaryLeaveInProgress = true
        isRunning = false
        val targets = members.keys.filter { it != myIp }
        // Enviar LEAVE varias veces — UDP no garantiza entrega y
        // un solo intento puede perderse al cerrar la conexión.
        repeat(3) {
            udp.broadcastSignal("LEAVE:$myIp", targets)
        }
        announceTimer?.cancel()
        timeoutTimer?.cancel()
        audio.stopCapture()
        members.clear()
    }
}
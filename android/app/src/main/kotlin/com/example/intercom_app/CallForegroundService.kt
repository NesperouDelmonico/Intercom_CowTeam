package com.example.intercom_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class CallForegroundService : Service() {

    companion object {
        const val ACTION_START   = "START"
        const val ACTION_STOP    = "STOP"
        const val ACTION_COMMAND = "COMMAND"
        private const val CHANNEL_ID = "intercom_call"
        private const val NOTIF_ID   = 1
        const val METHOD_CHANNEL = "com.example.intercom_app/call_service"
        const val EVENT_CHANNEL  = "com.example.intercom_app/call_events"
    }

    private var wakeLock:    PowerManager.WakeLock? = null
    private var audioEngine: AudioEngine? = null
    private var udpEngine:   UdpEngine?   = null
    private var roomEngine:  RoomEngine?  = null
    private var soundEngine: SoundEngine? = null
    private var mixerEngine: MixerEngine? = null

    private var isCallActive    = false
    private var currentRoomCode = ""

    override fun onCreate() {
        super.onCreate()
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioEngine = AudioEngine(am)
        udpEngine   = UdpEngine()
        soundEngine = SoundEngine(this)
        mixerEngine = MixerEngine(audioEngine!!)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val deviceName = intent.getStringExtra("deviceName") ?: "Sala activa"
                val myIp     = intent.getStringExtra("myIp")
                val myName   = intent.getStringExtra("myName")
                val myAvatar = intent.getStringExtra("myAvatar") ?: ""
                val roomCode = intent.getStringExtra("roomCode")

                startForeground(NOTIF_ID, buildNotification(deviceName))
                acquireWakeLock()

                if (myIp != null && myName != null && roomCode != null) {
                    startCall(myIp, myName, myAvatar, roomCode)
                }
            }
            ACTION_STOP -> {
                stopCall()
                releaseWakeLock()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_COMMAND -> {
                val cmd = intent.getStringExtra("command") ?: return START_STICKY
                handleCommand(cmd, intent)
            }
        }
        return START_STICKY
    }

    // ── COMANDOS ───────────────────────────────────────
    private fun handleCommand(cmd: String, intent: Intent) {
        when (cmd) {
            "setGain" -> {
                val gain = intent.getFloatExtra("gain", 1.0f)
                roomEngine?.setMicGain(gain)
            }
            "setVox" -> {
                val enabled   = intent.getBooleanExtra("enabled", false)
                val threshold = intent.getDoubleExtra("threshold", 500.0)
                roomEngine?.setVox(enabled, threshold)
            }
            "setMuted" -> {
                val muted = intent.getBooleanExtra("muted", false)
                roomEngine?.setMuted(muted)
            }
            "setMemberMuted" -> {
                val ip    = intent.getStringExtra("ip")    ?: return
                val muted = intent.getBooleanExtra("muted", false)
                roomEngine?.setMemberMuted(ip, muted)
            }
            "setMemberVolume" -> {
                val ip     = intent.getStringExtra("ip")     ?: return
                val volume = intent.getFloatExtra("volume", 1.0f)
                roomEngine?.setMemberVolume(ip, volume)
            }
            "setNoiseLevel" -> {
                val level = intent.getIntExtra("level", 1)
                roomEngine?.setNoiseLevel(level)
            }
            // ── Historial WiFi Direct para reconexión forzada ──
            // Flutter envía la MAC del dispositivo WiFi Direct asociado
            // a una IP de sala — se guarda en el RoomEngine para poder
            // pedir una reconexión forzada si la señal se pierde.
            "setMemberWifiDirectAddress" -> {
                val ip      = intent.getStringExtra("ip")      ?: return
                val address = intent.getStringExtra("address") ?: return
                roomEngine?.setMemberWifiDirectAddress(ip, address)
            }
            "stopCall" -> stopCall()
        }
    }

    // ── INICIAR LLAMADA ────────────────────────────────
    private fun startCall(
        myIp: String,
        myName: String,
        myAvatar: String,
        roomCode: String,
    ) {
        // Guard — si ya hay una llamada activa con el mismo código, ignorar
        if (isCallActive && currentRoomCode == roomCode) {
            return
        }

        // Si hay una llamada activa diferente, detenerla limpiamente
        if (isCallActive) {
            roomEngine?.leave()
            roomEngine = null
            audioEngine?.stopPlayback()
            udpEngine?.stop()
            udpEngine = UdpEngine()
        }

        isCallActive    = true
        currentRoomCode = roomCode

        udpEngine?.start()
        roomEngine = RoomEngine(udpEngine!!, audioEngine!!, soundEngine!!, mixerEngine!!)
        audioEngine?.startPlayback()
        roomEngine?.start(myIp, myName, myAvatar, roomCode)

        EventBus.send("callStarted", mapOf("roomCode" to roomCode))
    }

    // ── DETENER LLAMADA ────────────────────────────────
    private fun stopCall() {
        if (!isCallActive) return
        isCallActive    = false
        currentRoomCode = ""
        roomEngine?.leave()
        audioEngine?.stopPlayback()

        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            udpEngine?.stop()
            roomEngine = null
        }, 300L)

        EventBus.send("callStopped", null)
    }

    // ── NOTIFICACIÓN ───────────────────────────────────
    private fun buildNotification(deviceName: String): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Llamada activa",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                setSound(null, null)
                enableVibration(false)
            }
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }

        val openIntent = PendingIntent.getActivity(
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Intercom activo")
            .setContentText("En sala con $deviceName")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    // ── WAKE LOCK ──────────────────────────────────────
    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "IntercomApp::CallWakeLock"
        ).apply { acquire(4 * 60 * 60 * 1000L) }
    }

    private fun releaseWakeLock() {
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
        soundEngine?.release()
        stopCall()
        releaseWakeLock()
    }
}
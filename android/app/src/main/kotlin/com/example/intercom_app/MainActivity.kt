package com.example.intercom_app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import android.media.audiofx.AcousticEchoCanceler
import android.media.audiofx.AutomaticGainControl
import android.media.audiofx.NoiseSuppressor
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.sqrt
import android.content.Intent
import android.os.Build

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.intercom_app/audio"
    private var audioTrack: AudioTrack? = null
    private var audioManager: AudioManager? = null
    private var bluetoothHeadset: BluetoothHeadset? = null
    private var isBtActive = false
    private var currentAudioLevel: Float = 0f

    // VOX
    private var voxEnabled = false
    private var voxThreshold = 500.0
    private var callVolume = 1.0f

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
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        BluetoothAdapter.getDefaultAdapter()
            ?.getProfileProxy(this, headsetListener, BluetoothProfile.HEADSET)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startPlayback" -> { startAudioCall(); result.success(null) }
                    "playChunk" -> {
                        val bytes = call.argument<ByteArray>("data")
                        if (bytes != null) playChunk(bytes)
                        result.success(null)
                    }
                    "stopPlayback" -> { stopAudioCall(); result.success(null) }
                    "enableBluetooth" -> { enableBluetooth(); result.success(null) }
                    "disableBluetooth" -> { disableBluetooth(); result.success(null) }
                    "enableSpeaker" -> { enableSpeaker(); result.success(null) }
                    "disableSpeaker" -> { disableSpeaker(); result.success(null) }
                    "isBluetoothConnected" -> result.success(isBluetoothHeadsetConnected())
                    "setVox" -> {
                        voxEnabled = call.argument<Boolean>("enabled") ?: false
                        voxThreshold = (call.argument<Double>("threshold") ?: 500.0)
                        result.success(null)
                    }
                    "setVolume" -> {
                        callVolume = (call.argument<Double>("volume") ?: 1.0).toFloat()
                        result.success(null)
                    }
                    "startForegroundService" -> {
                        val deviceName = call.argument<String>("deviceName") ?: "Dispositivo"
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_START
                            putExtra("deviceName", deviceName)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    }
                    "stopForegroundService" -> {
                        val intent = Intent(this, CallForegroundService::class.java).apply {
                            action = CallForegroundService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "getAudioLevel" -> {
                        result.success(currentAudioLevel.toDouble())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isBluetoothHeadsetConnected(): Boolean {
        val adapter = BluetoothAdapter.getDefaultAdapter() ?: return false
        return adapter.isEnabled &&
            bluetoothHeadset?.connectedDevices?.isNotEmpty() == true
    }

    private fun startAudioCall() {
        audioManager?.mode = AudioManager.MODE_IN_COMMUNICATION

        if (isBluetoothHeadsetConnected()) {
            audioManager?.isSpeakerphoneOn = false
            audioManager?.isBluetoothScoOn = true
            audioManager?.startBluetoothSco()
            isBtActive = true
        } else {
            audioManager?.isSpeakerphoneOn = true
        }

        val sampleRate = 16000
        val bufferSize = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        audioTrack = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(bufferSize)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        audioTrack?.play()
        startAudioLevelMonitor()
    }

    private var audioLevelThread: Thread? = null
    private var isRecording = false

    private fun startAudioLevelMonitor() {
        val sampleRate = 16000
        val bufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )
        isRecording = true
        audioLevelThread = Thread {
            try {
                val audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.VOICE_COMMUNICATION,
                    sampleRate,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize
                )
                val buffer = ShortArray(bufferSize)
                audioRecord.startRecording()
                while (isRecording) {
                    val read = audioRecord.read(buffer, 0, bufferSize)
                    if (read > 0) {
                        var sum = 0.0
                        for (i in 0 until read) sum += buffer[i] * buffer[i]
                        val rms = sqrt(sum / read)
                        currentAudioLevel = (rms.toFloat() / 8000f).coerceIn(0f, 1f)
                    }
                }
                audioRecord.stop()
                audioRecord.release()
            } catch (_: Exception) {}
        }
        audioLevelThread?.start()
    }

    fun shouldTransmit(data: ByteArray): Boolean {
        if (!voxEnabled) return true
        var sum = 0.0
        for (i in 0 until data.size - 1 step 2) {
            val sample = (data[i].toInt() or (data[i + 1].toInt() shl 8)).toShort()
            sum += sample * sample
        }
        val rms = sqrt(sum / (data.size / 2))
        return rms > voxThreshold
    }

    private fun enableBluetooth() {
        if (isBluetoothHeadsetConnected()) {
            audioManager?.isSpeakerphoneOn = false
            audioManager?.isBluetoothScoOn = true
            audioManager?.startBluetoothSco()
            isBtActive = true
        }
    }

    private fun disableBluetooth() {
        audioManager?.isBluetoothScoOn = false
        audioManager?.stopBluetoothSco()
        audioManager?.isSpeakerphoneOn = true
        isBtActive = false
    }

    private fun enableSpeaker() {
        if (isBtActive) {
            audioManager?.isBluetoothScoOn = false
            audioManager?.stopBluetoothSco()
            isBtActive = false
        }
        audioManager?.isSpeakerphoneOn = true
    }

    private fun disableSpeaker() {
        audioManager?.isSpeakerphoneOn = false
    }

    private fun playChunk(data: ByteArray) {
        if (callVolume != 1.0f) {
            val shorts = ShortArray(data.size / 2)
            for (i in shorts.indices) {
                val s = (data[i * 2].toInt() or (data[i * 2 + 1].toInt() shl 8)).toShort()
                shorts[i] = (s * callVolume).toInt().coerceIn(-32768, 32767).toShort()
            }
            val scaled = ByteArray(data.size)
            for (i in shorts.indices) {
                scaled[i * 2] = (shorts[i].toInt() and 0xFF).toByte()
                scaled[i * 2 + 1] = (shorts[i].toInt() shr 8).toByte()
            }
            audioTrack?.write(scaled, 0, scaled.size)
        } else {
            audioTrack?.write(data, 0, data.size)
        }
    }

    private fun stopAudioCall() {

        isRecording = false
        audioLevelThread?.interrupt()
        audioLevelThread = null
        currentAudioLevel = 0f

        if (isBtActive) {
            audioManager?.isBluetoothScoOn = false
            audioManager?.stopBluetoothSco()
            isBtActive = false
        }
        audioManager?.isSpeakerphoneOn = false
        audioManager?.mode = AudioManager.MODE_NORMAL
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
    }
}
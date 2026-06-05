package com.example.intercom_app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.intercom_app/audio"
    private var audioTrack: AudioTrack? = null
    private var audioManager: AudioManager? = null
    private var bluetoothHeadset: BluetoothHeadset? = null
    private var isBtActive = false

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
                    "startPlayback" -> {
                        startAudioCall()
                        result.success(null)
                    }
                    "playChunk" -> {
                        val bytes = call.argument<ByteArray>("data")
                        if (bytes != null) playChunk(bytes)
                        result.success(null)
                    }
                    "stopPlayback" -> {
                        stopAudioCall()
                        result.success(null)
                    }
                    "enableBluetooth" -> {
                        enableBluetooth()
                        result.success(null)
                    }
                    "disableBluetooth" -> {
                        disableBluetooth()
                        result.success(null)
                    }
                    "isBluetoothConnected" -> {
                        result.success(isBluetoothHeadsetConnected())
                    }
                    "enableSpeaker" -> {
                        enableSpeaker()
                        result.success(null)
                    }
                    "disableSpeaker" -> {
                        disableSpeaker()
                        result.success(null)
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

    private fun playChunk(data: ByteArray) {
        audioTrack?.write(data, 0, data.size)
    }

    private fun stopAudioCall() {
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
}
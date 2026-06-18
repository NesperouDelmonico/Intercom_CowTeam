package com.example.intercom_app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTrack
import android.media.MediaRecorder
import kotlin.math.sqrt

class AudioEngine(private val audioManager: AudioManager) {

    companion object {
        const val SAMPLE_RATE   = 16000
        const val CHUNK_MS      = 20
        const val CHUNK_SAMPLES = SAMPLE_RATE * CHUNK_MS / 1000  // 320
        const val CHUNK_BYTES   = CHUNK_SAMPLES * 2              // 640
    }

    private var audioRecord:   AudioRecord? = null
    private var audioTrack:    AudioTrack?  = null
    private var captureThread: Thread?      = null

    @Volatile private var isCapturing = false

    var micGain:      Float   = 1.0f
    var voxEnabled:   Boolean = false
    var voxThreshold: Double  = 500.0

    var onAudioCaptured: ((ByteArray) -> Unit)? = null

    // ── CAPTURA ────────────────────────────────────────
    fun startCapture() {
        if (isCapturing) return

        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        val record = AudioRecord(
            MediaRecorder.AudioSource.VOICE_COMMUNICATION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(minBuffer, CHUNK_BYTES * 4)
        )

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            record.release()
            return
        }

        audioRecord = record
        isCapturing = true

        captureThread = Thread {
            val buffer = ByteArray(CHUNK_BYTES)

            try {
                audioRecord?.startRecording()
            } catch (e: Exception) {
                isCapturing = false
                audioRecord?.release()
                audioRecord = null
                return@Thread
            }

            while (isCapturing) {
                val read = audioRecord?.read(buffer, 0, CHUNK_BYTES) ?: break
                if (read <= 0) continue

                val chunk  = buffer.copyOf(read)
                val gained = applyGain(chunk, micGain)

                if (!voxEnabled || shouldTransmit(gained)) {
                    onAudioCaptured?.invoke(gained)
                }
            }

            // Detener solo si está en estado activo
            try {
                if (audioRecord?.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    audioRecord?.stop()
                }
            } catch (_: Exception) {}

            audioRecord?.release()
            audioRecord = null
        }

        captureThread?.priority = Thread.MAX_PRIORITY
        captureThread?.start()
    }

    fun stopCapture() {
        isCapturing = false
        captureThread?.interrupt()
        captureThread = null
        // audioRecord se limpia en el hilo de captura
    }

    // ── REPRODUCCIÓN ───────────────────────────────────
    fun startPlayback(useBluetooth: Boolean = false) {
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION

        if (useBluetooth) {
            audioManager.isSpeakerphoneOn = false
            audioManager.isBluetoothScoOn = true
            audioManager.startBluetoothSco()
        } else {
            audioManager.isSpeakerphoneOn = true
        }

        val minBuffer = AudioTrack.getMinBufferSize(
            SAMPLE_RATE,
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
                    .setSampleRate(SAMPLE_RATE)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(minBuffer)
            .setTransferMode(AudioTrack.MODE_STREAM)
            .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
            .build()

        audioTrack?.play()
    }

    fun playChunk(data: ByteArray, volume: Float = 1.0f) {
    val track = audioTrack ?: return

    // Flush agresivo si hay más de 80ms acumulados
    val queued = track.playbackHeadPosition.let { head ->
        val written = track.notificationMarkerPosition
        if (written > head) written - head else 0
    }
    if (queued > SAMPLE_RATE * 80 / 1000) { // 80ms
        track.pause()
        track.flush()
        track.play()
        return
    }

    val scaled = if (volume != 1.0f) applyGain(data, volume) else data
    track.write(scaled, 0, scaled.size)
    }

    fun stopPlayback() {
        audioManager.isSpeakerphoneOn = false
        audioManager.isBluetoothScoOn = false
        audioManager.stopBluetoothSco()
        audioManager.mode = AudioManager.MODE_NORMAL
        try {
            audioTrack?.stop()
        } catch (_: Exception) {}
        audioTrack?.release()
        audioTrack = null
    }

    // ── PROCESAMIENTO ──────────────────────────────────
    private fun applyGain(data: ByteArray, gain: Float): ByteArray {
        if (gain == 1.0f) return data
        val result = ByteArray(data.size)
        var i = 0
        while (i < data.size - 1) {
            val s = (data[i].toInt() and 0xFF) or
                    ((data[i + 1].toInt() and 0xFF) shl 8)
            val signed    = if (s > 32767) s - 65536 else s
            val amplified = (signed * gain).toInt().coerceIn(-32768, 32767)
            result[i]     = (amplified and 0xFF).toByte()
            result[i + 1] = ((amplified shr 8) and 0xFF).toByte()
            i += 2
        }
        return result
    }

    private fun shouldTransmit(data: ByteArray): Boolean {
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
        return rms > voxThreshold
    }

    fun release() {
        stopCapture()
        stopPlayback()
    }
}
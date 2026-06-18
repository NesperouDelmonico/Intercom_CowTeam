package com.example.intercom_app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.sin

class SoundEngine(private val context: Context) {

    private val sampleRate = 44100
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    // ── SONIDO DE ENTRADA ──────────────────────────────
    // Dos tonos ascendentes cortos — similar a Discord join
    fun playJoin() {
        Thread {
            playTone(noteFreq = 880.0, durationMs = 120, volumeStart = 0.0f, volumeEnd = 0.7f)
            Thread.sleep(60)
            playTone(noteFreq = 1100.0, durationMs = 160, volumeStart = 0.5f, volumeEnd = 0.0f)
        }.start()
    }

    // ── SONIDO DE SALIDA ───────────────────────────────
    // Dos tonos descendentes cortos — opuesto al join
    fun playLeave() {
        Thread {
            playTone(noteFreq = 660.0, durationMs = 120, volumeStart = 0.6f, volumeEnd = 0.4f)
            Thread.sleep(50)
            playTone(noteFreq = 440.0, durationMs = 180, volumeStart = 0.4f, volumeEnd = 0.0f)
        }.start()
    }

    // ── GENERADOR DE TONO ──────────────────────────────
    private fun playTone(
        noteFreq:    Double,
        durationMs:  Int,
        volumeStart: Float,
        volumeEnd:   Float,
    ) {
        val numSamples = sampleRate * durationMs / 1000
        val samples    = ShortArray(numSamples)

        for (i in 0 until numSamples) {
            // Envolvente de volumen lineal (fade in/out)
            val envelope = volumeStart + (volumeEnd - volumeStart) * i / numSamples
            // Onda sinusoidal
            val angle = 2.0 * PI * noteFreq * i / sampleRate
            samples[i] = (sin(angle) * envelope * Short.MAX_VALUE).toInt().toShort()
        }

        val minBuffer = AudioTrack.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_OUT_MONO,
            AudioFormat.ENCODING_PCM_16BIT
        )

        val track = AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(sampleRate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build()
            )
            .setBufferSizeInBytes(maxOf(minBuffer, samples.size * 2))
            .setTransferMode(AudioTrack.MODE_STATIC)
            .build()

        try {
            track.write(samples, 0, samples.size)
            track.play()
            Thread.sleep(durationMs.toLong() + 20)
        } catch (_: Exception) {
        } finally {
            track.stop()
            track.release()
        }
    }

    fun release() {
        // No hay recursos persistentes, pero podríamos limpiar si los tuviéramos
    }

}
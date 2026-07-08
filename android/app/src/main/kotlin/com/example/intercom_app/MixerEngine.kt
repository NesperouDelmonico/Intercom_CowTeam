package com.example.intercom_app

import java.util.concurrent.ConcurrentHashMap

/**
 * Mezclador de audio con diseño "audio-clock driven".
 *
 * El principio central: audioTrack.write() en modo bloqueante ES el
 * reloj. Cuando el buffer del hardware está lleno, write() espera
 * automáticamente hasta que haya espacio — y ese espacio se libera
 * exactamente a la tasa de reproducción real (16000 muestras/seg).
 *
 * Esto elimina el problema de timing que teníamos con schedulers y
 * Thread.sleep(), que en Android no son tiempo real y causaban huecos
 * (el audio "titilante").
 *
 * Por cada ciclo de escritura, el mixer construye un chunk de 20ms:
 *   - toma el chunk más antiguo de cada fuente que ya tiene colchón
 *   - si hay varias fuentes activas, las mezcla y normaliza
 *   - si hay una sola, la usa directa
 *   - si no hay ninguna, escribe silencio (mantiene el stream vivo)
 */
class MixerEngine(private val audio: AudioEngine) {

    companion object {
        val CHUNK_BYTES = AudioEngine.CHUNK_BYTES
        // Chunks mínimos acumulados de una fuente antes de empezar a
        // consumirla — colchón de jitter. 3 chunks ≈ 60ms de margen
        // para absorber variación de latencia de red entre saltos.
        const val JITTER_MIN_CHUNKS = 3
        // Máximo de chunks en buffer por fuente. Mantenerlo bajo evita
        // el "buffer creep" — si el emisor captura ligeramente más
        // rápido de lo que reproducimos, el buffer crecería hasta
        // cortar el audio a los pocos segundos. Con 5 chunks (~100ms)
        // descartamos los viejos de forma suave antes de llegar a ese
        // punto, manteniendo la latencia acotada.
        const val MAX_BUFFER_CHUNKS = 5
    }

    // Estado de cada fuente de audio (una por IP remota)
    private class Source {
        val chunks = ArrayDeque<ByteArray>()
        // true una vez que acumuló el colchón mínimo y ya está
        // "fluyendo" — a partir de ahí se consume continuamente.
        var flowing = false
    }

    private val sources = ConcurrentHashMap<String, Source>()

    // Deduplicación de chunks — un mismo chunk puede llegar por dos
    // caminos en topologías mesh heterogéneas. ID = IP:timestamp.
    private val seenIds = object : LinkedHashMap<String, Unit>(256, 0.75f, true) {
        override fun removeEldestEntry(eldest: Map.Entry<String, Unit>) = size > 200
    }

    @Volatile private var isRunning = false
    private var playbackThread: Thread? = null

    // ── INICIAR ────────────────────────────────────────
    fun start() {
        if (isRunning) return
        isRunning = true
        playbackThread = Thread {
            try {
                runMixLoop()
            } catch (_: InterruptedException) {
                // Interrupción esperada al detener
            } catch (_: Exception) {
                // Nunca dejar que una excepción tumbe el proceso
            }
        }.apply {
            priority = Thread.MAX_PRIORITY
            start()
        }
    }

    // ── BUCLE PRINCIPAL ────────────────────────────────
    // audio.writeBlocking() marca el ritmo — cuando el buffer del
    // hardware está lleno, bloquea; cuando libera espacio (a la tasa
    // real de reproducción), retorna y construimos el siguiente chunk.
    private fun runMixLoop() {
        while (isRunning) {
            val chunk = buildNextChunk()
            audio.writeBlocking(chunk)
        }
    }

    // Construye el siguiente chunk de 20ms mezclando las fuentes
    // que ya están fluyendo (tienen colchón suficiente).
    private fun buildNextChunk(): ByteArray {
        val ready = mutableListOf<ByteArray>()

        for ((_, source) in sources) {
            synchronized(source) {
                // Marcar como "fluyendo" una vez que acumuló el colchón
                if (!source.flowing && source.chunks.size >= JITTER_MIN_CHUNKS) {
                    source.flowing = true
                }
                // Solo consumir de fuentes que ya están fluyendo
                if (source.flowing) {
                    val c = source.chunks.removeFirstOrNull()
                    if (c != null) {
                        ready.add(c)
                    } else {
                        // Se quedó sin chunks — resetear el colchón para
                        // que vuelva a acumular antes de reanudar (evita
                        // reproducir de a goteo cuando la señal es débil).
                        source.flowing = false
                    }
                }
            }
        }

        return when {
            ready.isEmpty()   -> ByteArray(CHUNK_BYTES) // silencio
            ready.size == 1   -> ready[0]               // fuente única
            else              -> mix(ready)             // mezcla
        }
    }

    // ── RECIBIR CHUNK ──────────────────────────────────
    fun push(fromIp: String, timestamp: Long, data: ByteArray) {
        val id = "$fromIp:$timestamp"
        synchronized(seenIds) {
            if (seenIds.containsKey(id)) return
            seenIds[id] = Unit
        }

        val source = sources.getOrPut(fromIp) { Source() }
        synchronized(source) {
            if (source.chunks.size >= MAX_BUFFER_CHUNKS) {
                source.chunks.removeFirst()
            }
            source.chunks.addLast(data)
        }
    }

    // ── MEZCLA PCM16 ───────────────────────────────────
    private fun mix(chunks: List<ByteArray>): ByteArray {
        val size   = chunks.minOf { it.size }
        val result = ByteArray(size)
        val count  = chunks.size

        var i = 0
        while (i < size - 1) {
            var sum = 0
            for (chunk in chunks) {
                val s      = (chunk[i].toInt() and 0xFF) or
                             ((chunk[i + 1].toInt() and 0xFF) shl 8)
                sum       += if (s > 32767) s - 65536 else s
            }
            val normalized = (sum / count).coerceIn(-32768, 32767)
            result[i]     = (normalized and 0xFF).toByte()
            result[i + 1] = ((normalized shr 8) and 0xFF).toByte()
            i += 2
        }
        return result
    }

    // ── LIMPIAR FUENTE ─────────────────────────────────
    fun removeMember(ip: String) {
        sources.remove(ip)
    }

    // ── DETENER ────────────────────────────────────────
    fun stop() {
        isRunning = false
        playbackThread?.interrupt()
        playbackThread = null
        sources.clear()
        synchronized(seenIds) { seenIds.clear() }
    }
}
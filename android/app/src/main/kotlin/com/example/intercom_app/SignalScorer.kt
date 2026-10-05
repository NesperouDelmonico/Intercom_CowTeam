package com.example.intercom_app

/**
 * Calidad de señal de un miembro, de 0 (sin señal) a 3 (buena).
 *
 * Función pura: no toca Android ni estado, para poder probarla con un
 * test unitario sin dispositivos. Combina dos dimensiones y devuelve la
 * peor de las dos (una señal solo es buena si es reciente Y constante):
 *
 *  • Latencia: tiempo desde el último paquete recibido, medido en
 *    múltiplos del intervalo de ANNOUNCE (así sigue siendo válida si el
 *    intervalo cambia, p. ej. en un futuro modo ahorro).
 *  • Tasa de recepción: ANNOUNCEs recibidos vs. esperados en la ventana
 *    observada. Los umbrales son generosos porque UDP pierde paquetes
 *    ocasionalmente incluso con buena señal.
 */
object SignalScorer {

    fun score(
        elapsedMs: Long,   // ahora - último paquete (cualquier tipo) del miembro
        received: Int,     // ANNOUNCEs distintos recibidos dentro de la ventana
        observedMs: Long,  // cuánto lleva observándose al miembro (tope = ventana)
        intervalMs: Long,  // intervalo con el que se emiten los ANNOUNCE
        timeoutMs: Long,   // tiempo tras el cual el miembro pasa a offline
    ): Int {
        val interval = intervalMs.coerceAtLeast(1L)

        val latencyScore = when {
            elapsedMs < interval * 3 / 2 -> 3
            elapsedMs < interval * 5 / 2 -> 2
            elapsedMs < timeoutMs        -> 1
            else                         -> 0
        }

        // Un miembro recién visto no ha tenido tiempo de "acumular" una
        // ventana completa: esperamos solo lo que cabe en lo observado.
        val expected = (observedMs / interval).toInt().coerceAtLeast(1)
        val ratio = received.toFloat() / expected
        val rateScore = when {
            ratio >= 0.8f -> 3
            ratio >= 0.5f -> 2
            ratio >= 0.2f -> 1
            else          -> 0
        }

        return minOf(latencyScore, rateScore)
    }
}

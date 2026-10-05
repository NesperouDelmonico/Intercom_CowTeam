package com.example.intercom_app

import org.junit.Assert.assertEquals
import org.junit.Test

class SignalScorerTest {

    private fun score(elapsed: Long, received: Int, observed: Long = 5_000L,
                      interval: Long = 1_000L, timeout: Long = 3_000L) =
        SignalScorer.score(elapsed, received, observed, interval, timeout)

    @Test fun senalPlenaSiTodoLlegaYEsReciente() =
        assertEquals(3, score(elapsed = 200, received = 5))

    @Test fun latenciaBajaLosUmbrales() {
        assertEquals(3, score(elapsed = 1_499, received = 5))
        assertEquals(2, score(elapsed = 1_500, received = 5))
        assertEquals(2, score(elapsed = 2_499, received = 5))
        assertEquals(1, score(elapsed = 2_500, received = 5))
        assertEquals(1, score(elapsed = 2_999, received = 5))
        assertEquals(0, score(elapsed = 3_000, received = 5))
    }

    @Test fun perdidaDePaquetesBajaElScore() {
        assertEquals(3, score(elapsed = 200, received = 4)) // 0.8
        assertEquals(2, score(elapsed = 200, received = 3)) // 0.6
        assertEquals(1, score(elapsed = 200, received = 2)) // 0.4
        assertEquals(0, score(elapsed = 200, received = 0))
    }

    @Test fun gananLosDosPeoresDeLasDimensiones() {
        // Reciente pero con muchas pérdidas -> manda la tasa.
        assertEquals(1, score(elapsed = 200, received = 2))
        // Sin pérdidas pero el último paquete es viejo -> manda la latencia.
        assertEquals(1, score(elapsed = 2_700, received = 5))
    }

    @Test fun miembroRecienVistoNoSePenaliza() {
        assertEquals(3, score(elapsed = 100, received = 1, observed = 800))
        assertEquals(3, score(elapsed = 100, received = 1, observed = 0))
    }

    @Test fun seAdaptaAUnIntervaloMayor() {
        // ANNOUNCE cada 3 s: 3.5 s sin paquetes sigue siendo buena señal.
        assertEquals(3, score(elapsed = 3_500, received = 1,
            interval = 3_000, timeout = 9_000))
    }
}

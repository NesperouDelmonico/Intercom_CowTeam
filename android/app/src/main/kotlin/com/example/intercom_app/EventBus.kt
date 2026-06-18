package com.example.intercom_app

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

object EventBus {
    private var sink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())

    fun setSink(sink: EventChannel.EventSink?) {
        this.sink = sink
    }

    fun send(type: String, data: Any?) {
        handler.post {
            sink?.success(mapOf("type" to type, "data" to data))
        }
    }
}
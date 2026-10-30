package com.designer1974.devoo_radio

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Activity compatibile con la riproduzione in background (notifica con i controlli)
class MainActivity : AudioServiceActivity() {
    private var channel: MethodChannel? = null

    // Il telefono si sta spegnendo: la registrazione si chiude subito (al riavvio si recupera)
    private val shutdown = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            StreamRecorder.shutdown()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val f = IntentFilter(Intent.ACTION_SHUTDOWN)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(shutdown, f, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(shutdown, f)
            }
        } catch (_: Exception) {}
    }

    override fun onDestroy() {
        try { unregisterReceiver(shutdown) } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rr/recorder")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "streamStart" -> {
                        StreamRecorder.start(
                            call.argument<String>("url")!!,
                            call.argument<String>("dir")!!,
                            call.argument<String>("name")!!,
                            call.argument<String>("dst")!!,
                            call.argument<Int>("bitrate")!!,
                            call.argument<Int>("outCh")!!,
                            call.argument<Boolean>("he")!!,
                        )
                        result.success(null)
                    }
                    "streamStatus" -> result.success(
                        mapOf(
                            "running" to StreamRecorder.running,
                            "bytes" to StreamRecorder.bytes,
                            "error" to StreamRecorder.error,
                        )
                    )
                    "streamStop" -> Thread {
                        val p = try { StreamRecorder.stop() } catch (e: Exception) { null }
                        runOnUiThread { result.success(p) }
                    }.start()
                    "recover" -> Thread {
                        val l = try { StreamRecorder.recover(call.argument<String>("dir")!!) } catch (e: Exception) { emptyList() }
                        runOnUiThread { result.success(l) }
                    }.start()
                    "schedAdd" -> {
                        val m = call.arguments as Map<*, *>
                        val j = org.json.JSONObject()
                        for ((k, v) in m) j.put(k.toString(), v)
                        Scheduler.add(this, j)
                        result.success(null)
                    }
                    "schedList" -> {
                        val a = Scheduler.all(this)
                        result.success((0 until a.length()).map { i ->
                            val o = a.getJSONObject(i)
                            o.keys().asSequence().associateWith { k -> o.get(k) }
                        })
                    }
                    "schedRemove" -> {
                        val id = call.argument<String>("id")!!
                        if (Scheduler.get(this, id)?.optBoolean("running") == true) {
                            try {
                                startService(Intent(this, ScheduledRecService::class.java).setAction(ScheduledRecService.ACTION_STOP))
                            } catch (_: Exception) {}
                        }
                        Scheduler.remove(this, id)
                        result.success(null)
                    }
                    "schedExactOk" -> result.success(Scheduler.exactAllowed(this))
                    "schedExactSettings" -> {
                        if (Build.VERSION.SDK_INT >= 31) {
                            try {
                                startActivity(Intent(android.provider.Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                    android.net.Uri.parse("package:$packageName")))
                            } catch (_: Exception) {}
                        }
                        result.success(null)
                    }
                    "duration" -> {
                        val path = call.argument<String>("path")!!
                        Thread {
                            val d = AudioTools.durationMs(path)
                            runOnUiThread { result.success(d) }
                        }.start()
                    }
                    "toM4a" -> background(result) { report ->
                        AudioTools.wavToM4a(
                            call.argument<String>("src")!!,
                            call.argument<String>("dst")!!,
                            call.argument<Int>("bitrate")!!,
                            call.argument<Int>("outCh")!!,
                            call.argument<Boolean>("he")!!,
                            report,
                        )
                    }
                    "toWav" -> background(result) { report ->
                        AudioTools.toWav(
                            call.argument<String>("src")!!,
                            call.argument<String>("dst")!!,
                            report,
                        )
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("REC", e.message ?: "Errore", null)
            }
        }
    }

    /** Lavoro pesante in un thread, con avanzamento verso Flutter. */
    private fun background(result: MethodChannel.Result, work: ((Double) -> Unit) -> Unit) {
        Thread {
            try {
                work { p -> runOnUiThread { channel?.invokeMethod("progress", p) } }
                runOnUiThread { result.success(null) }
            } catch (e: Exception) {
                runOnUiThread { result.error("CODEC", e.message ?: "Errore audio", null) }
            }
        }.start()
    }
}

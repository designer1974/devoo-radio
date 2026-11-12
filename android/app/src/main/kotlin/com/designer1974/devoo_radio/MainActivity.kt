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
    private var pickResult: MethodChannel.Result? = null

    /** Copia nella cache i file audio scelti e restituisce i percorsi (nome originale). */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 4711) return
        val res = pickResult ?: return
        pickResult = null
        if (resultCode != RESULT_OK || data == null) { res.success(emptyList<String>()); return }
        val uris = mutableListOf<android.net.Uri>()
        data.clipData?.let { c -> for (i in 0 until c.itemCount) uris.add(c.getItemAt(i).uri) }
        if (uris.isEmpty()) data.data?.let { uris.add(it) }
        Thread {
            val out = mutableListOf<String>()
            val dir = java.io.File(cacheDir, "import").apply { deleteRecursively(); mkdirs() }
            for (u in uris) {
                try {
                    var name = "Registrazione.m4a"
                    contentResolver.query(u, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                        if (c.moveToFirst()) c.getString(0)?.let { name = it }
                    }
                    name = name.replace('/', ' ')
                    var f = java.io.File(dir, name)
                    var k = 2
                    while (f.exists()) f = java.io.File(dir, "${k++}_$name")
                    contentResolver.openInputStream(u)?.use { inp -> f.outputStream().use { inp.copyTo(it, 1 shl 16) } }
                    out.add(f.absolutePath)
                } catch (_: Exception) {}
            }
            runOnUiThread { res.success(out) }
        }.start()
    }

    // Il telefono si sta spegnendo: la registrazione si chiude subito (al riavvio si recupera)
    private val shutdown = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            StreamRecorder.shutdown()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Se l'app si chiude da sola, il motivo viene scritto in un file e mostrato alla prossima apertura
        try {
            val dir = filesDir
            val prev = Thread.getDefaultUncaughtExceptionHandler()
            if (prev !is CrashCatcher) Thread.setDefaultUncaughtExceptionHandler(CrashCatcher(dir, prev))
        } catch (_: Exception) {}
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
        try { Scheduler.refreshStandby(this) } catch (_: Exception) {}
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
                            "busy" to StreamRecorder.busy,
                            "bytes" to StreamRecorder.bytes,
                            "error" to StreamRecorder.error,
                            "startedAt" to StreamRecorder.startedAt,
                            "url" to StreamRecorder.url,
                            "schedId" to ScheduledRecService.activeId,
                            "schedName" to ScheduledRecService.activeName,
                            "schedFlag" to ScheduledRecService.activeFlag,
                            "schedEnd" to ScheduledRecService.activeEnd,
                        )
                    )
                    "schedStop" -> {
                        try {
                            startService(Intent(this, ScheduledRecService::class.java).setAction(ScheduledRecService.ACTION_STOP))
                        } catch (_: Exception) {}
                        result.success(null)
                    }
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
                        val a = Scheduler.list(this)
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
                    "batteryOk" -> {
                        val pm = getSystemService(POWER_SERVICE) as android.os.PowerManager
                        result.success(Build.VERSION.SDK_INT < 23 || pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "batteryAsk" -> {
                        if (Build.VERSION.SDK_INT >= 23) {
                            try {
                                startActivity(Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    android.net.Uri.parse("package:$packageName")))
                            } catch (_: Exception) {
                                try { startActivity(Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) } catch (_: Exception) {}
                            }
                        }
                        result.success(null)
                    }
                    "lastCrash" -> {
                        val f = java.io.File(filesDir, "crash.txt")
                        val t = if (f.exists()) f.readText() else null
                        f.delete()
                        result.success(t)
                    }
                    "is64" -> result.success(Build.SUPPORTED_64_BIT_ABIS.isNotEmpty())
                    "openUrl" -> {
                        val ok = try {
                            startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(call.argument<String>("url")!!))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true
                        } catch (_: Exception) { false }
                        result.success(ok)
                    }
                    "appInfo" -> {
                        val ui = getSystemService(UI_MODE_SERVICE) as android.app.UiModeManager
                        val tv = ui.currentModeType == android.content.res.Configuration.UI_MODE_TYPE_TELEVISION ||
                            packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_LEANBACK)
                        // id del dispositivo: serve per il codice dispositivo della licenza Pro
                        val id = try {
                            android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ANDROID_ID) ?: ""
                        } catch (_: Exception) { "" }
                        result.success(mapOf("package" to packageName, "tv" to tv, "id" to id, "model" to "${Build.MANUFACTURER} ${Build.MODEL}"))
                    }
                    "installedAt" -> result.success(
                        try { packageManager.getPackageInfo(packageName, 0).lastUpdateTime } catch (_: Exception) { 0L }
                    )
                    "installStatus" -> {
                        val p = getSharedPreferences("devoo_update", MODE_PRIVATE)
                        result.success(mapOf("status" to p.getInt("status", -100), "msg" to (p.getString("msg", "") ?: "")))
                    }
                    "installApk" -> Thread {
                        val r = try { installApk(call.argument<String>("path")!!); "ok" } catch (e: Exception) { e.message ?: "errore" }
                        runOnUiThread { result.success(r) }
                    }.start()
                    "isHuawei" -> result.success(
                        Build.MANUFACTURER.equals("HUAWEI", true) || Build.MANUFACTURER.equals("HONOR", true)
                    )
                    "openAutostart" -> {
                        // pagina "Avvio app" di Huawei/Honor; se non c'è, le impostazioni dell'app
                        val tries = listOf(
                            android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                            android.content.ComponentName("com.huawei.systemmanager", "com.huawei.systemmanager.optimize.process.ProtectActivity"),
                            android.content.ComponentName("com.hihonor.systemmanager", "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
                        )
                        var ok = false
                        for (c in tries) {
                            try { startActivity(Intent().setComponent(c).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); ok = true; break } catch (_: Exception) {}
                        }
                        if (!ok) {
                            try {
                                startActivity(Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    android.net.Uri.parse("package:$packageName")))
                            } catch (_: Exception) {}
                        }
                        result.success(ok)
                    }
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
                    "pickAudio" -> {
                        pickResult?.success(emptyList<String>())
                        pickResult = result
                        val i = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "audio/*"
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                        }
                        try { startActivityForResult(i, 4711) } catch (e: Exception) {
                            pickResult = null
                            result.error("PICK", e.message, null)
                        }
                    }
                    "toWav16k" -> Thread {
                        try {
                            val ms = AudioTools.toWav16k(
                                call.argument<String>("src")!!,
                                call.argument<String>("dst")!!,
                                (call.argument<Number>("start") ?: 0).toLong(),
                                (call.argument<Number>("end") ?: 0).toLong(),
                            ) { p -> runOnUiThread { channel?.invokeMethod("progress", p) } }
                            runOnUiThread { result.success(ms) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("CODEC", e.message ?: "Errore audio", null) }
                        }
                    }.start()
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

    /**
     * Aggiornamento: passa l'APK scaricato all'installatore di Android (PackageInstaller).
     * Il sistema poi mostra la conferma "Installa" con un pulsante normale.
     */
    private fun installApk(path: String) {
        val f = java.io.File(path)
        getSharedPreferences("devoo_update", MODE_PRIVATE).edit().putInt("status", -100).putString("msg", "").commit()
        val pi = packageManager.packageInstaller
        val params = android.content.pm.PackageInstaller.SessionParams(
            android.content.pm.PackageInstaller.SessionParams.MODE_FULL_INSTALL
        )
        val id = pi.createSession(params)
        pi.openSession(id).use { s ->
            f.inputStream().use { input ->
                s.openWrite("update.apk", 0, f.length()).use { out ->
                    input.copyTo(out, 256 * 1024)
                    s.fsync(out)
                }
            }
            val flags = android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 31) android.app.PendingIntent.FLAG_MUTABLE else 0)
            val sender = android.app.PendingIntent.getBroadcast(
                this, id, Intent(this, InstallReceiver::class.java), flags
            ).intentSender
            s.commit(sender)
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

class CrashCatcher(private val dir: java.io.File, private val prev: Thread.UncaughtExceptionHandler?) :
    Thread.UncaughtExceptionHandler {
    override fun uncaughtException(t: Thread, e: Throwable) {
        try {
            val sw = java.io.StringWriter()
            e.printStackTrace(java.io.PrintWriter(sw))
            java.io.File(dir, "crash.txt").writeText(
                "Android ${Build.VERSION.RELEASE} · ${Build.MANUFACTURER} ${Build.MODEL}\nThread: ${t.name}\n" +
                    sw.toString().take(6000)
            )
        } catch (_: Throwable) {}
        prev?.uncaughtException(t, e)
    }
}

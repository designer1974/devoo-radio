package com.designer1974.devoo_radio

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Calendar

/**
 * Registrazioni programmate: funzionano anche ad app chiusa e schermo spento.
 * Tutto in Kotlin (non serve Flutter acceso): sveglia di sistema -> servizio -> registra -> si ferma.
 */
object Scheduler {
    private const val TAG = "Scheduler"
    private const val PREFS = "devoo_schedules"
    private const val KEY = "list"
    private const val DAY = 24L * 3600 * 1000

    @Synchronized
    fun all(ctx: Context): JSONArray =
        try { JSONArray(ctx.getSharedPreferences(PREFS, 0).getString(KEY, "[]")) } catch (_: Exception) { JSONArray() }

    @Synchronized
    private fun save(ctx: Context, a: JSONArray) {
        ctx.getSharedPreferences(PREFS, 0).edit().putString(KEY, a.toString()).apply()
    }

    fun get(ctx: Context, id: String): JSONObject? {
        val a = all(ctx)
        for (i in 0 until a.length()) if (a.getJSONObject(i).optString("id") == id) return a.getJSONObject(i)
        return null
    }

    @Synchronized
    fun put(ctx: Context, j: JSONObject) {
        val a = all(ctx)
        val out = JSONArray()
        for (i in 0 until a.length()) if (a.getJSONObject(i).optString("id") != j.optString("id")) out.put(a.getJSONObject(i))
        out.put(j)
        save(ctx, out)
    }

    @Synchronized
    fun remove(ctx: Context, id: String) {
        cancel(ctx, id)
        val a = all(ctx)
        val out = JSONArray()
        for (i in 0 until a.length()) if (a.getJSONObject(i).optString("id") != id) out.put(a.getJSONObject(i))
        save(ctx, out)
    }

    fun add(ctx: Context, j: JSONObject) {
        j.put("running", false)
        put(ctx, j)
        arm(ctx, j)
    }

    fun exactAllowed(ctx: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val am = (ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
        return am.canScheduleExactAlarms()
    }

    /** Sposta un programma "ogni giorno" al prossimo giorno utile. */
    fun rollForward(j: JSONObject) {
        val now = System.currentTimeMillis()
        while (j.getLong("end") <= now) {
            j.put("start", shiftDay(j.getLong("start")))
            j.put("end", shiftDay(j.getLong("end")))
        }
    }

    // stesso orario il giorno dopo (corretto anche col cambio dell'ora legale)
    private fun shiftDay(t: Long): Long {
        val c = Calendar.getInstance()
        c.timeInMillis = t
        c.add(Calendar.DAY_OF_YEAR, 1)
        return c.timeInMillis
    }

    fun arm(ctx: Context, j: JSONObject) {
        val id = j.getString("id")
        val start = j.getLong("start")
        val end = j.getLong("end")
        val now = System.currentTimeMillis()
        if (end <= now) return
        if (start <= now) { // già dentro l'orario: parte subito
            startRec(ctx, id)
            return
        }
        val am = (ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
        val pi = alarmIntent(ctx, id)
        try {
            if (exactAllowed(ctx)) {
                val show = PendingIntent.getActivity(
                    ctx, 0, Intent(ctx, MainActivity::class.java),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                am.setAlarmClock(AlarmManager.AlarmClockInfo(start, show), pi)
            } else if (Build.VERSION.SDK_INT >= 23) {
                am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, start, pi)
            } else {
                am.set(AlarmManager.RTC_WAKEUP, start, pi)
            }
        } catch (e: Exception) {
            Log.w(TAG, "sveglia non impostata", e)
            am.set(AlarmManager.RTC_WAKEUP, start, pi)
        }
    }

    fun armAll(ctx: Context) {
        val a = all(ctx)
        for (i in 0 until a.length()) {
            val j = a.getJSONObject(i)
            j.put("running", false)
            if (j.optBoolean("daily")) rollForward(j)
            if (j.getLong("end") <= System.currentTimeMillis()) {
                remove(ctx, j.getString("id"))
            } else {
                put(ctx, j)
                arm(ctx, j)
            }
        }
    }

    fun cancel(ctx: Context, id: String) {
        try { (ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(alarmIntent(ctx, id)) } catch (_: Exception) {}
    }

    private fun alarmIntent(ctx: Context, id: String): PendingIntent =
        PendingIntent.getBroadcast(
            ctx, id.hashCode(),
            Intent(ctx, RecAlarmReceiver::class.java).setAction("devoo.rec.$id").putExtra("id", id),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

    fun startRec(ctx: Context, id: String) {
        val i = Intent(ctx, ScheduledRecService::class.java).putExtra("id", id)
        try {
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        } catch (e: Exception) {
            Log.e(TAG, "servizio non avviato", e)
        }
    }
}

class RecAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getStringExtra("id") ?: return
        Scheduler.startRec(context, id)
    }
}

/** Dopo il riavvio del telefono le sveglie vanno reimpostate. */
class RecBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        try { Scheduler.armAll(context) } catch (_: Exception) {}
    }
}

class ScheduledRecService : Service() {
    companion object {
        const val ACTION_STOP = "devoo.rec.STOP"
        private const val CHANNEL = "devoo_rec_sched"
        private const val NOTIF = 7101
    }

    private val handler = Handler(Looper.getMainLooper())
    private var currentId: String? = null
    private var wake: PowerManager.WakeLock? = null
    private var finishing = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            showForeground("Salvataggio…")
            finish()
            return START_NOT_STICKY
        }
        val id = intent?.getStringExtra("id")
        val j = id?.let { Scheduler.get(this, it) }
        if (j == null || currentId != null) {
            if (currentId == null) { showForeground("Devoo Radio Pro"); stopSelf() }
            return START_NOT_STICKY
        }
        val name = j.optString("name")
        val end = j.getLong("end")
        val now = System.currentTimeMillis()
        val c = Calendar.getInstance().apply { timeInMillis = end }
        showForeground("● Registro $name fino alle %02d:%02d".format(c.get(Calendar.HOUR_OF_DAY), c.get(Calendar.MINUTE)))
        if (end <= now || StreamRecorder.busy) {
            if (StreamRecorder.busy) Log.w("ScheduledRec", "c'è già una registrazione in corso")
            currentId = id
            finish()
            return START_NOT_STICKY
        }
        currentId = id
        wake = (getSystemService(POWER_SERVICE) as PowerManager)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "devoo:schedrec").apply {
                setReferenceCounted(false)
                acquire(end - now + 120_000)
            }
        try {
            val dir = j.getString("dir")
            File(dir).mkdirs()
            val st = Calendar.getInstance().apply { timeInMillis = now }
            val title = "${j.optString("flag")} $name %02d-%02d %02d.%02d".format(
                st.get(Calendar.DAY_OF_MONTH), st.get(Calendar.MONTH) + 1,
                st.get(Calendar.HOUR_OF_DAY), st.get(Calendar.MINUTE)
            ).trim()
            StreamRecorder.start(
                j.getString("url"), dir, ".rec_$now", unique(dir, title),
                j.optInt("bitrate", 32000), j.optInt("outCh", 2), j.optBoolean("he", true),
            )
            j.put("running", true)
            Scheduler.put(this, j)
        } catch (e: Exception) {
            Log.e("ScheduledRec", "avvio", e)
            finish()
            return START_NOT_STICKY
        }
        handler.postDelayed({ finish() }, end - now)
        return START_NOT_STICKY
    }

    private fun unique(dir: String, name: String): String {
        val base = name.replace(Regex("[\\\\/:*?\"<>|\\n\\r\\t]"), " ").replace(Regex("\\s+"), " ").trim()
            .ifEmpty { "Registrazione" }
        var f = File(dir, "$base.m4a")
        var n = 2
        while (f.exists()) { f = File(dir, "$base ($n).m4a"); n++ }
        return f.absolutePath
    }

    private fun finish() {
        if (finishing) return
        finishing = true
        handler.removeCallbacksAndMessages(null)
        val id = currentId
        Thread {
            try { StreamRecorder.stop() } catch (e: Exception) { Log.e("ScheduledRec", "stop", e) }
            if (id != null) {
                val j = Scheduler.get(this, id)
                if (j != null && j.optBoolean("daily")) {
                    j.put("running", false)
                    Scheduler.rollForward(j)
                    Scheduler.put(this, j)
                    Scheduler.arm(this, j)
                } else if (j != null) {
                    Scheduler.remove(this, id)
                }
            }
            handler.post {
                try { wake?.release() } catch (_: Exception) {}
                currentId = null
                finishing = false
                if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
                stopSelf()
            }
        }.start()
    }

    private fun showForeground(text: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(CHANNEL) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL, "Registrazioni programmate", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val open = PendingIntent.getActivity(
            this, 1, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val stop = PendingIntent.getService(
            this, 2, Intent(this, ScheduledRecService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
        val b = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL)
        else @Suppress("DEPRECATION") Notification.Builder(this)
        val n = b.setContentTitle("Devoo Radio Pro")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.presence_audio_online)
            .setOngoing(true)
            .setContentIntent(open)
            .addAction(
                @Suppress("DEPRECATION")
                Notification.Action.Builder(android.R.drawable.ic_media_pause, "Ferma e salva", stop).build()
            )
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIF, n)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        try { wake?.release() } catch (_: Exception) {}
        super.onDestroy()
    }
}

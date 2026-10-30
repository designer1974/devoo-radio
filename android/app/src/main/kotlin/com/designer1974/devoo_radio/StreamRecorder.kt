package com.designer1974.devoo_radio

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.LinkedBlockingQueue

/**
 * Registra direttamente lo stream della radio (qualità originale, nessun popup).
 *
 * I byte arrivano in pezzi da ~2 minuti; mentre si registra, un secondo thread
 * comprime ogni pezzo finito in un unico file M4A (AAC). Così quando si preme
 * "Ferma" resta da comprimere solo l'ultimo pezzo: il salvataggio è quasi immediato.
 */
object StreamRecorder {
    private const val TAG = "StreamRecorder"
    private const val CHUNK_MS = 120_000L
    private val DONE = File("")

    @Volatile var running = false
        private set
    @Volatile var bytes = 0L
        private set
    @Volatile var error: String? = null
        private set

    private var thread: Thread? = null
    private var worker: Thread? = null
    @Volatile private var conn: HttpURLConnection? = null
    private val queue = LinkedBlockingQueue<File>()
    @Volatile private var encoded = false

    private var base = ""
    private var dir = ""
    private var dst = ""

    fun start(url: String, dir: String, name: String, dst: String, bitrate: Int, outCh: Int, he: Boolean) {
        stop()
        bytes = 0
        error = null
        encoded = false
        queue.clear()
        running = true
        this.base = name
        this.dir = dir
        this.dst = dst
        // promemoria per il recupero se il telefono si spegne
        File(dir, "$name.json").writeText(
            "{\"dst\":${org.json.JSONObject.quote(dst)},\"bitrate\":$bitrate,\"outCh\":$outCh,\"he\":$he}"
        )
        val enc = SegEncoder(dir, name, bitrate, outCh, he, 0)
        worker = Thread({ work(enc) }, "stream-enc").apply { start() }
        thread = Thread({ loop(url, dir, name) }, "stream-rec").apply { start() }
    }

    /** Ferma, finisce la compressione e unisce i pezzi. Ritorna il file M4A o null. */
    @Synchronized
    fun stop(): String? {
        val w = worker ?: return null
        running = false
        try { conn?.disconnect() } catch (_: Exception) {}
        try { thread?.join(5000) } catch (_: Exception) {}
        thread = null
        try { w.join(120_000) } catch (_: Exception) {}
        worker = null
        val ok = encoded && merge(dir, base, dst)
        if (ok) File(dir, "$base.json").delete()
        return if (ok) dst else null
    }

    /** Spegnimento del telefono: si ferma subito il download; il resto lo fa [recover] al riavvio. */
    fun shutdown() {
        running = false
        try { conn?.disconnect() } catch (_: Exception) {}
    }

    /**
     * Registrazioni interrotte (telefono spento, app chiusa dal sistema):
     * comprime i pezzi rimasti e unisce tutto. Ritorna i file recuperati.
     */
    @Synchronized
    fun recover(dir: String): List<String> {
        if (worker != null) return emptyList()
        val out = mutableListOf<String>()
        val d = File(dir)
        for (side in d.listFiles { f -> f.name.endsWith(".json") && f.name.startsWith(".rec_") } ?: emptyArray()) {
            val name = side.name.removeSuffix(".json")
            try {
                val j = org.json.JSONObject(side.readText())
                val target = j.getString("dst")
                d.listFiles { f -> f.name.startsWith("$name.seg") && f.name.endsWith(".tmp") }?.forEach { it.delete() }
                val parts = (d.listFiles { f -> f.name.startsWith("$name.part") } ?: emptyArray())
                    .sortedBy { it.name.substringAfter(".part").substringBefore('.').toIntOrNull() ?: 0 }
                if (parts.isNotEmpty()) {
                    val enc = SegEncoder(dir, name, j.getInt("bitrate"), j.getInt("outCh"), j.getBoolean("he"), nextSeg(d, name))
                    for (p in parts) {
                        try { enc.feed(p.absolutePath) } catch (e: Exception) { Log.w(TAG, "recupero pezzo", e) }
                        enc.rotate()
                        p.delete()
                    }
                    enc.finish()
                }
                if (merge(dir, name, target)) out.add(target)
            } catch (e: Exception) {
                Log.w(TAG, "recupero non riuscito", e)
            }
            // pulizia
            d.listFiles { f -> f.name.startsWith("$name.") }?.forEach { it.delete() }
        }
        return out
    }

    private fun nextSeg(d: File, name: String): Int =
        (d.listFiles { f -> f.name.startsWith("$name.seg") && f.name.endsWith(".m4a") } ?: emptyArray())
            .maxOfOrNull { it.name.substringAfter(".seg").substringBefore('.').toIntOrNull() ?: 0 }?.plus(1) ?: 0

    /** Unisce i pezzi M4A (stessa codifica) in un unico file, senza ricomprimere: pochi secondi. */
    private fun merge(dir: String, name: String, target: String): Boolean {
        val segs = (File(dir).listFiles { f -> f.name.startsWith("$name.seg") && f.name.endsWith(".m4a") } ?: emptyArray())
            .sortedBy { it.name.substringAfter(".seg").substringBefore('.').toIntOrNull() ?: 0 }
            .filter { it.length() > 0 }
        if (segs.isEmpty()) return false
        val tmp = File("$target.tmp")
        var muxer: android.media.MediaMuxer? = null
        var track = -1
        var offset = 0L
        var wrote = false
        val buf = java.nio.ByteBuffer.allocate(256 * 1024)
        val info = MediaCodec.BufferInfo()
        try {
            for (seg in segs) {
                val ex = MediaExtractor()
                try {
                    ex.setDataSource(seg.absolutePath)
                    if (ex.trackCount == 0) continue
                    ex.selectTrack(0)
                    if (muxer == null) {
                        muxer = android.media.MediaMuxer(tmp.absolutePath, android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                        track = muxer.addTrack(ex.getTrackFormat(0))
                        muxer.start()
                    }
                    var last = -1L
                    var step = 23_000L
                    while (true) {
                        val n = ex.readSampleData(buf, 0)
                        if (n < 0) break
                        val t = ex.sampleTime
                        if (last >= 0 && t > last) step = t - last
                        last = t
                        info.set(0, n, offset + t, MediaCodec.BUFFER_FLAG_KEY_FRAME)
                        muxer.writeSampleData(track, buf, info)
                        wrote = true
                        ex.advance()
                    }
                    if (last >= 0) offset += last + step
                } catch (e: Exception) {
                    Log.w(TAG, "pezzo rovinato saltato: ${seg.name}", e)
                } finally {
                    ex.release()
                }
            }
        } finally {
            try { if (wrote) muxer?.stop() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
        }
        if (!wrote) { tmp.delete(); return false }
        val f = File(target)
        f.delete()
        if (!tmp.renameTo(f)) return false
        segs.forEach { it.delete() }
        return true
    }

    // ---------- download ----------

    private fun open(start: String): HttpURLConnection {
        var u = start
        repeat(6) {
            val c = URL(u).openConnection() as HttpURLConnection
            c.instanceFollowRedirects = false
            c.connectTimeout = 15000
            c.readTimeout = 20000
            c.setRequestProperty("User-Agent", "DevooRadio/1.0")
            c.setRequestProperty("Accept", "*/*")
            val code = c.responseCode
            if (code in 300..399) {
                val loc = c.getHeaderField("Location") ?: throw IllegalStateException("Redirect senza indirizzo")
                c.disconnect()
                u = URL(URL(u), loc).toString() // anche http <-> https
                return@repeat
            }
            if (code !in 200..299) {
                c.disconnect()
                throw IllegalStateException("La radio risponde $code")
            }
            return c
        }
        throw IllegalStateException("Troppi reindirizzamenti")
    }

    private fun extFor(type: String, url: String): String? {
        val t = type.lowercase()
        val u = url.lowercase().substringBefore('?')
        if (t.contains("mpegurl") || u.endsWith(".m3u8")) return null // HLS: non registrabile
        return when {
            t.contains("aac") || t.contains("mp4") || u.endsWith(".aac") -> "aac"
            t.contains("ogg") || t.contains("opus") || u.endsWith(".ogg") -> "ogg"
            else -> "mp3"
        }
    }

    /** Inizio di un frame audio (per tagliare i pezzi in un punto pulito). -1 se non c'è. */
    private fun syncAt(b: ByteArray, n: Int, ext: String): Int {
        for (i in 0 until n - 1) {
            if (b[i] != 0xFF.toByte()) continue
            val x = b[i + 1].toInt() and 0xFF
            if (ext == "aac") {
                if (x and 0xF6 != 0xF0) continue
                // controlla che il frame dopo inizi davvero dove dice la lunghezza
                if (i + 6 < n) {
                    val len = ((b[i + 3].toInt() and 0x03) shl 11) or
                        ((b[i + 4].toInt() and 0xFF) shl 3) or ((b[i + 5].toInt() and 0xE0) shr 5)
                    val j = i + len
                    if (len < 7) continue
                    if (j + 1 < n && !(b[j] == 0xFF.toByte() && (b[j + 1].toInt() and 0xF6) == 0xF0)) continue
                    if (j + 1 >= n) continue
                    return i
                }
            } else if (x and 0xE0 == 0xE0 && (x and 0x18) != 0x08 && (x and 0x06) != 0) {
                return i
            }
        }
        return -1
    }

    private fun loop(url: String, dir: String, name: String) {
        var out: FileOutputStream? = null
        var chunk: File? = null
        var part = 0
        var ext = "mp3"
        var chunkStart = 0L
        var fails = 0
        val buf = ByteArray(16 * 1024)

        fun newChunk() {
            chunk = File(dir, "$name.part$part.$ext")
            part++
            out = FileOutputStream(chunk!!)
            chunkStart = System.currentTimeMillis()
        }

        fun closeChunk() {
            try { out?.flush(); out?.close() } catch (_: Exception) {}
            out = null
            chunk?.let { queue.put(it) }
            chunk = null
        }

        try {
            while (running) {
                var input: InputStream? = null
                try {
                    val c = open(url)
                    conn = c
                    if (out == null) {
                        ext = extFor(c.contentType ?: "", c.url.toString())
                            ?: throw IllegalArgumentException("Questa radio usa un formato (HLS) che non si può registrare")
                        newChunk()
                    }
                    val src = c.inputStream
                    input = src
                    while (running) {
                        val n = src.read(buf)
                        if (n < 0) break
                        bytes += n
                        fails = 0
                        // ogni 2 minuti un pezzo nuovo (non per ogg: le intestazioni sono solo all'inizio)
                        val rotate = ext != "ogg" && System.currentTimeMillis() - chunkStart > CHUNK_MS
                        val cut = if (rotate) syncAt(buf, n, ext) else -1
                        if (cut >= 0) {
                            if (cut > 0) out!!.write(buf, 0, cut)
                            closeChunk()
                            newChunk()
                            out!!.write(buf, cut, n - cut)
                        } else {
                            out!!.write(buf, 0, n)
                        }
                    }
                } catch (e: IllegalArgumentException) {
                    error = e.message
                    running = false
                } catch (e: Exception) {
                    if (!running) break
                    Log.w(TAG, "connessione persa, riprovo", e)
                    if (++fails > 15) {
                        error = "Connessione alla radio persa"
                        running = false
                    } else {
                        Thread.sleep(2000)
                    }
                } finally {
                    try { input?.close() } catch (_: Exception) {}
                    try { conn?.disconnect() } catch (_: Exception) {}
                }
            }
        } finally {
            closeChunk()
            running = false
            queue.put(DONE)
        }
    }

    // ---------- compressione ----------

    private fun work(enc: SegEncoder) {
        try {
            while (true) {
                val f = queue.take()
                if (f === DONE) break
                try {
                    enc.feed(f.absolutePath)
                } catch (e: Exception) {
                    Log.w(TAG, "pezzo non decodificato: ${f.name}", e)
                } finally {
                    enc.rotate() // pezzo M4A completo sul disco: sopravvive allo spegnimento
                    f.delete()
                }
            }
        } finally {
            encoded = enc.finish()
        }
    }

    /** Decodifica un file audio e passa il PCM a [sink] (dati, lunghezza, frequenza, canali). */
    fun decode(src: String, progress: ((Double) -> Unit)?, sink: (ByteArray, Int, Int, Int) -> Unit) {
        val total = File(src).length().coerceAtLeast(1)
        val ex = MediaExtractor()
        try {
            ex.setDataSource(src)
            var t = -1
            for (i in 0 until ex.trackCount) {
                val mime = ex.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) { t = i; break }
            }
            if (t < 0) throw IllegalStateException("Audio non riconosciuto")
            ex.selectTrack(t)
            val fmt = ex.getTrackFormat(t)
            val dec = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
            dec.configure(fmt, null, null, 0)
            dec.start()
            var rate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var ch = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val info = MediaCodec.BufferInfo()
            var tmp = ByteArray(0)
            var inDone = false
            var outDone = false
            var read = 0L
            var lastReport = 0L
            try {
                while (!outDone) {
                    if (!inDone) {
                        val i = dec.dequeueInputBuffer(10_000)
                        if (i >= 0) {
                            val b = dec.getInputBuffer(i)!!
                            val n = ex.readSampleData(b, 0)
                            if (n < 0) {
                                dec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inDone = true
                            } else {
                                dec.queueInputBuffer(i, 0, n, ex.sampleTime.coerceAtLeast(0), 0)
                                ex.advance()
                                read += n
                                if (progress != null && read - lastReport > 500_000) {
                                    lastReport = read
                                    progress((read.toDouble() / total).coerceIn(0.0, 0.99))
                                }
                            }
                        }
                    }
                    val o = dec.dequeueOutputBuffer(info, 10_000)
                    if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val f = dec.outputFormat
                        rate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        ch = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    } else if (o >= 0) {
                        val b = dec.getOutputBuffer(o)!!
                        if (info.size > 0) {
                            if (tmp.size < info.size) tmp = ByteArray(info.size)
                            b.position(info.offset)
                            b.get(tmp, 0, info.size)
                            sink(tmp, info.size - info.size % (ch * 2), rate, ch)
                        }
                        dec.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outDone = true
                    }
                }
            } finally {
                try { dec.stop() } catch (_: Exception) {}
                try { dec.release() } catch (_: Exception) {}
            }
        } finally {
            ex.release()
        }
    }

    /**
     * Un solo codificatore AAC continuo (nessun "click" tra i pezzi);
     * l'uscita viene scritta in file M4A separati, chiusi a ogni [rotate].
     */
    private class SegEncoder(
        val dir: String, val name: String, val bitrate: Int, val outCh: Int, val he: Boolean, startIndex: Int,
    ) {
        private var codec: MediaCodec? = null
        private var rate = 0
        private var inCh = 0
        private var ch = 1
        private var frames = 0L
        private var fmt: MediaFormat? = null
        private var muxer: android.media.MediaMuxer? = null
        private var track = -1
        private var segFile: File? = null
        private var segBase = -1L
        private var index = startIndex
        private var wrote = false
        private var mono = ByteArray(0)
        private val info = MediaCodec.BufferInfo()

        private fun make(he: Boolean): MediaCodec? {
            var c: MediaCodec? = null
            return try {
                val f = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, rate, ch)
                f.setInteger(MediaFormat.KEY_BIT_RATE, bitrate)
                f.setInteger(
                    MediaFormat.KEY_AAC_PROFILE,
                    if (he) android.media.MediaCodecInfo.CodecProfileLevel.AACObjectHE
                    else android.media.MediaCodecInfo.CodecProfileLevel.AACObjectLC
                )
                f.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 65536)
                c = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC)
                c.configure(f, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                c.start()
                c
            } catch (e: Exception) {
                try { c?.release() } catch (_: Exception) {}
                null
            }
        }

        fun feed(src: String) {
            decode(src, null) { data, len, r, c -> write(data, len, r, c) }
        }

        private fun write(pcm: ByteArray, len: Int, r: Int, c: Int) {
            if (len <= 0) return
            if (codec == null) {
                rate = r; inCh = c; ch = minOf(outCh, c).coerceAtLeast(1)
                codec = make(he) ?: make(false) ?: throw IllegalStateException("Codifica AAC non disponibile")
            }
            if (r != rate || c != inCh) return // formato cambiato a metà: si salta
            val cc = codec!!
            var data = pcm
            var size = len
            if (ch == 1 && inCh == 2) {
                val n = len / 4
                if (mono.size < n * 2) mono = ByteArray(n * 2)
                for (i in 0 until n) {
                    val p = i * 4
                    val l = (pcm[p].toInt() and 0xff) or (pcm[p + 1].toInt() shl 8)
                    val rr = (pcm[p + 2].toInt() and 0xff) or (pcm[p + 3].toInt() shl 8)
                    val m = (l + rr) / 2
                    mono[i * 2] = (m and 0xff).toByte()
                    mono[i * 2 + 1] = ((m shr 8) and 0xff).toByte()
                }
                data = mono; size = n * 2
            }
            val frameBytes = ch * 2
            var pos = 0
            while (pos < size) {
                val idx = cc.dequeueInputBuffer(10_000)
                if (idx >= 0) {
                    val b = cc.getInputBuffer(idx)!!
                    b.clear()
                    var n = minOf(b.remaining(), size - pos)
                    n -= n % frameBytes
                    if (n <= 0) n = minOf(frameBytes, size - pos)
                    b.put(data, pos, n)
                    cc.queueInputBuffer(idx, 0, n, frames * 1_000_000L / rate, 0)
                    frames += n / frameBytes
                    pos += n
                }
                drain(false)
            }
        }

        private fun drain(eos: Boolean) {
            val cc = codec ?: return
            var idle = 0
            while (true) {
                val o = cc.dequeueOutputBuffer(info, if (eos) 10_000 else 0)
                when {
                    o == MediaCodec.INFO_TRY_AGAIN_LATER -> if (!eos || ++idle > 300) return
                    o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> fmt = cc.outputFormat
                    o >= 0 -> {
                        val b = cc.getOutputBuffer(o)!!
                        if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) info.size = 0
                        if (info.size > 0 && fmt != null) {
                            val m = muxer ?: openSeg()
                            if (segBase < 0) segBase = info.presentationTimeUs
                            b.position(info.offset)
                            b.limit(info.offset + info.size)
                            val out = MediaCodec.BufferInfo()
                            out.set(0, info.size, (info.presentationTimeUs - segBase).coerceAtLeast(0), info.flags)
                            m.writeSampleData(track, b.slice(), out)
                            wrote = true
                        }
                        cc.releaseOutputBuffer(o, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) return
                    }
                }
            }
        }

        private fun openSeg(): android.media.MediaMuxer {
            val f = File(dir, "$name.seg%04d.tmp".format(index++))
            val m = android.media.MediaMuxer(f.absolutePath, android.media.MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            track = m.addTrack(fmt!!)
            m.start()
            muxer = m
            segFile = f
            segBase = -1
            return m
        }

        /** Chiude il pezzo attuale: diventa un file M4A valido. */
        fun rotate() {
            val m = muxer ?: return
            muxer = null
            try { m.stop() } catch (e: Exception) { Log.w(TAG, "chiusura pezzo", e) }
            try { m.release() } catch (_: Exception) {}
            segFile?.let { f -> f.renameTo(File(f.path.removeSuffix(".tmp") + ".m4a")) }
            segFile = null
        }

        fun finish(): Boolean {
            val cc = codec
            if (cc != null) {
                try {
                    var tries = 0
                    while (tries++ < 100) {
                        val idx = cc.dequeueInputBuffer(10_000)
                        if (idx >= 0) {
                            cc.queueInputBuffer(idx, 0, 0, frames * 1_000_000L / rate, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            break
                        }
                        drain(false)
                    }
                    drain(true)
                } catch (e: Exception) {
                    Log.w(TAG, "fine codifica", e)
                } finally {
                    try { cc.stop() } catch (_: Exception) {}
                    try { cc.release() } catch (_: Exception) {}
                    codec = null
                }
            }
            rotate()
            return wrote
        }
    }
}

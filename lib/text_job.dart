// Il lavoro «crea testo + traduzione» vive fuori dalla pagina:
// se esci e rientri, la pagina ritrova la barra al punto giusto
// e, quando finisce, mostra subito il testo.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart' show tr;
import 'transcript.dart';
import 'translate_online.dart';
import 'whisper_service.dart';

class TextJob extends ChangeNotifier {
  TextJob._(this.path);
  final String path;

  static final _jobs = <String, TextJob>{};
  static TextJob? of(String path) => _jobs[path];
  static const _ch = MethodChannel('rr/recorder');
  static final _whisper = WhisperService();

  bool running = true;
  String stage = '';
  double? progress;
  String? error; // messaggio da mostrare alla fine (una volta)
  String? warning; // es. traduzione non riuscita

  String get _key => 'readerJob|${path.split('/').last}';

  void _set(String s, double? p) {
    stage = s;
    progress = p;
    notifyListeners();
  }

  static Future<void> _screen(bool on) async {
    try {
      await _ch.invokeMethod('keepScreenOn', {'on': on});
    } catch (_) {}
  }

  Future<void> _mark(String? s) async {
    try {
      final p = await SharedPreferences.getInstance();
      s == null ? await p.remove(_key) : await p.setString(_key, s);
    } catch (_) {}
  }

  /// Crea il testo (e poi la traduzione). Se è già in corso, restituisce quello.
  static TextJob create(String path,
      {required Quality quality,
      required String lang,
      required int startMs,
      required int endMs,
      required String target}) {
    final old = _jobs[path];
    if (old != null && old.running) return old;
    final j = _jobs[path] = TextJob._(path);
    j._runCreate(quality, lang, startMs, endMs, target);
    return j;
  }

  /// Solo la traduzione (testo già pronto).
  static TextJob translate(String path, String target) {
    final old = _jobs[path];
    if (old != null && old.running) return old;
    final j = _jobs[path] = TextJob._(path);
    j._runTranslateOnly(target);
    return j;
  }

  /// Aggiunge al testo i minuti successivi (dopo la fine del testo attuale).
  static TextJob extend(String path,
      {required Quality quality, required int minutes, required String target}) {
    final old = _jobs[path];
    if (old != null && old.running) return old;
    final j = _jobs[path] = TextJob._(path);
    j._runExtend(quality, minutes, target);
    return j;
  }

  Future<void> _runExtend(Quality q, int minutes, String target) async {
    await _screen(true);
    _set(tr('Preparo…'), null);
    try {
      final t = await loadTranscript(path);
      if (t == null || t.lines.isEmpty) throw Exception('nessun testo da continuare');
      final start = t.to > 0 ? t.to : t.lines.last.e;
      final end = start + minutes * 60000;
      final more = await _whisper.transcribe(path,
          quality: q, lang: t.lang.isEmpty ? 'auto' : t.lang, startMs: start, endMs: end, onStage: (s, p) => _set(tr(s), p));
      final added = more.lines.where((l) => l.s >= start - 300).toList();
      final merged = Transcript(t.lang, t.model, [...t.lines, ...added],
          tr: t.translations, tc: t.chunks, from: t.from, to: end);
      await saveTranscript(path, merged);
      if (added.isEmpty) {
        warning = '${tr('Nessun parlato tra')} ${fmtMs(start)} ${tr('e')} ${fmtMs(end)}.';
      } else {
        final langs = merged.translations.keys.toList();
        if (langs.isEmpty) langs.add(dstFor(merged.lang, target));
        for (final dst in langs) {
          await _translate(merged, dst, from: t.lines.length);
        }
      }
    } catch (e) {
      error = '$e';
    } finally {
      await _screen(false);
      running = false;
      notifyListeners();
    }
  }

  /// Lingua di arrivo: se coincide con quella della radio, ne sceglie un'altra.
  static String dstFor(String src, String target) => target != src ? target : (src == 'ar' ? 'it' : 'ar');

  Future<void> _runCreate(Quality q, String lang, int startMs, int endMs, String target) async {
    await _screen(true);
    var last = '';
    _set(tr('Preparo…'), null);
    try {
      final t = await _whisper.transcribe(path, quality: q, lang: lang, startMs: startMs, endMs: endMs,
          onStage: (s, p) {
        final base = s.replaceAll(RegExp(r'\s*\d+%$'), '');
        if (base != last) {
          last = base;
          _mark(base);
        }
        _set(tr(s), p);
      });
      if (t.lines.isEmpty) {
        error = tr('Non ho sentito parlato in questo pezzo. Prova un altro minuto.');
        return;
      }
      if (t.lang.isEmpty) {
        t.lang = await OnlineTranslator.detect(t.lines.map((l) => l.text).take(10).join(' ')) ?? 'es';
      }
      await saveTranscript(path, t);
      await _translate(t, dstFor(t.lang, target));
    } catch (e) {
      error = '$e';
    } finally {
      await _mark(null);
      await _screen(false);
      running = false;
      notifyListeners();
    }
  }

  Future<void> _runTranslateOnly(String target) async {
    await _screen(true);
    try {
      final t = await loadTranscript(path);
      if (t != null) await _translate(t, dstFor(t.lang, target));
    } finally {
      await _screen(false);
      running = false;
      notifyListeners();
    }
  }

  /// Traduce a pezzi (tra le virgole): l'ombra sulla traduzione segue meglio la voce.
  Future<void> _translate(Transcript t, String dst, {int from = 0}) async {
    final n = t.lines.length;
    _set('${tr('Traduco')}… $from/$n', 0);
    try {
      final pieces = <String>[];
      final owner = <int>[]; // frase di ogni pezzo
      final starts = <List<int>>[];
      for (var i = from; i < n; i++) {
        final l = t.lines[i];
        final st = chunkStarts(l);
        starts.add(st);
        for (var c = 0; c < st.length; c++) {
          final end = c + 1 < st.length ? st[c + 1] : l.words.length;
          pieces.add(l.words.sublist(st[c], end).map((w) => w.t).join(' '));
          owner.add(i);
        }
      }
      final out = await OnlineTranslator.lines(pieces, t.lang, dst,
          progress: (k) => _set('${tr('Traduco')}… ${k == pieces.length ? n : owner[k.clamp(0, owner.length - 1)]}/$n',
              k / pieces.length));
      final lines = List.generate(n - from, (_) => <String>[]);
      final tc = List.generate(n - from, (_) => <int>[]);
      var k = 0;
      for (var i = 0; i < n - from; i++) {
        for (final s0 in starts[i]) {
          final txt = k < out.length ? out[k].trim() : '';
          k++;
          final words = txt.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          lines[i].add(txt);
          tc[i]
            ..add(s0)
            ..add(words);
        }
      }
      final newTr = [for (final l in lines) l.where((x) => x.isNotEmpty).join(' ')];
      if (from == 0) {
        t.translations[dst] = newTr;
        t.chunks[dst] = tc;
      } else {
        // aggiunge in fondo (riempie eventuali buchi)
        final oldTr = List<String>.of(t.translations[dst] ?? const []);
        final oldTc = List<List<int>>.of(t.chunks[dst] ?? const []);
        while (oldTr.length < from) {
          oldTr.add('');
        }
        while (oldTc.length < from) {
          oldTc.add(<int>[]);
        }
        t.translations[dst] = [...oldTr.take(from), ...newTr];
        t.chunks[dst] = [...oldTc.take(from), ...tc];
      }
      await saveTranscript(path, t);
    } catch (_) {
      warning = tr('Testo pronto, ma la traduzione non è riuscita: serve internet. Riprova con ⋮ → Traduci di nuovo.');
    }
  }
}

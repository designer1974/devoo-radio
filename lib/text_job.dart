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
      {required Quality quality, required String lang, required int startMs, required int endMs}) {
    final old = _jobs[path];
    if (old != null && old.running) return old;
    final j = _jobs[path] = TextJob._(path);
    j._runCreate(quality, lang, startMs, endMs);
    return j;
  }

  /// Solo la traduzione (testo già pronto).
  static TextJob translate(String path) {
    final old = _jobs[path];
    if (old != null && old.running) return old;
    final j = _jobs[path] = TextJob._(path);
    j._runTranslateOnly();
    return j;
  }

  Future<void> _runCreate(Quality q, String lang, int startMs, int endMs) async {
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
      await _translate(t);
    } catch (e) {
      error = '$e';
    } finally {
      await _mark(null);
      await _screen(false);
      running = false;
      notifyListeners();
    }
  }

  Future<void> _runTranslateOnly() async {
    await _screen(true);
    try {
      final t = await loadTranscript(path);
      if (t != null) await _translate(t);
    } finally {
      await _screen(false);
      running = false;
      notifyListeners();
    }
  }

  Future<void> _translate(Transcript t) async {
    final dst = t.lang == 'ar' ? 'it' : 'ar';
    final n = t.lines.length;
    _set('${tr('Traduco')}… 0/$n', 0);
    try {
      final out = await OnlineTranslator.lines(t.lines.map((l) => l.text).toList(), t.lang, dst,
          progress: (k) => _set('${tr('Traduco')}… $k/$n', k / n));
      t.translations[dst] = out;
      await saveTranscript(path, t);
    } catch (_) {
      warning = tr('Testo pronto, ma la traduzione non è riuscita: serve internet. Riprova con ⋮ → Traduci di nuovo.');
    }
  }
}

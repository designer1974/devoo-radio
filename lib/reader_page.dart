// «Leggi e traduci»: il testo della registrazione come un libro.
// Mentre si sente la voce, un'ombra passa sulle parole.
//  · Originale: la voce vera della radio, parola per parola (per imparare a leggere).
//  · Arabo:     la traduzione letta dalla voce araba del telefono, parola per parola.
//  · Alterna:   frase originale, poi la stessa frase in arabo (come nel Corano del sito).

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart' show tr;
import 'transcript.dart';
import 'whisper_service.dart';
import 'widgets.dart' show accent;

/// Lingue dell'audio che sappiamo trascrivere e tradurre.
const readerLangs = <String, (String, String)>{
  'es': ('🇪🇸', 'Español'),
  'en': ('🇬🇧', 'English'),
  'fr': ('🇫🇷', 'Français'),
  'it': ('🇮🇹', 'Italiano'),
  'de': ('🇩🇪', 'Deutsch'),
  'pt': ('🇵🇹', 'Português'),
  'ar': ('🇸🇦', 'العربية'),
  'tr': ('🇹🇷', 'Türkçe'),
  'nl': ('🇳🇱', 'Nederlands'),
  'ru': ('🇷🇺', 'Русский'),
};

String _flagOf(String code) => readerLangs[code]?.$1 ?? '🌐';
String _nameOf(String code) => readerLangs[code]?.$2 ?? code.toUpperCase();

/// Dalla bandiera della radio (es. 🇲🇽) alla lingua probabile (es).
String guessLang(String? flag) {
  if (flag == null) return 'auto';
  final r = flag.runes.toList();
  if (r.length != 2 || r.any((c) => c < 0x1F1E6 || c > 0x1F1FF)) return 'auto';
  final cc = String.fromCharCodes(r.map((c) => c - 0x1F1E6 + 65));
  const es = 'ES MX AR CO CL PE VE EC GT CU BO DO HN PY SV NI CR PA UY PR GQ';
  const en = 'US GB IE AU NZ CA JM';
  const fr = 'FR BE LU MC SN CI CM';
  const ar = 'MA DZ TN LY EG SA AE QA KW BH OM YE JO LB SY IQ PS SD MR';
  const de = 'DE AT LI';
  const pt = 'PT BR AO MZ';
  if (es.contains(cc)) return 'es';
  if (en.contains(cc)) return 'en';
  if (fr.contains(cc)) return 'fr';
  if (ar.contains(cc)) return 'ar';
  if (de.contains(cc)) return 'de';
  if (pt.contains(cc)) return 'pt';
  if (cc == 'IT' || cc == 'SM' || cc == 'VA') return 'it';
  if (cc == 'TR') return 'tr';
  if (cc == 'NL') return 'nl';
  if (cc == 'RU') return 'ru';
  return 'auto';
}

TranslateLanguage? _ml(String code) {
  for (final l in TranslateLanguage.values) {
    if (l.bcpCode == code) return l;
  }
  return null;
}

enum ReadMode { original, translation, alternate }

class ReaderPage extends StatefulWidget {
  /// File audio; null = esempio spagnolo/arabo.
  final String? path;
  final String name;
  final String? flag;
  final Duration? duration;
  const ReaderPage({super.key, this.path, required this.name, this.flag, this.duration});

  const ReaderPage.sample({super.key})
      : path = null,
        name = 'Esempio · Español → العربية',
        flag = '🇪🇸',
        duration = null;

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _whisper = WhisperService();
  final _player = AudioPlayer();
  final _tts = FlutterTts();
  final _keys = <GlobalKey>[];

  Transcript? _t;
  bool _loading = true;

  // creazione del testo
  bool _working = false;
  String _stage = '';
  double? _progress;
  late String _lang = guessLang(widget.flag);
  int _startMin = 0;
  int _lenMin = 5; // 0 = tutto
  Quality _quality = Quality.balanced;

  // lettura
  ReadMode _mode = ReadMode.original;
  bool _slow = false;
  bool _playing = false;
  int _line = -1;
  int _word = -1;
  bool _phaseTr = false; // in «Alterna»: sta leggendo la traduzione
  int _gen = 0; // ogni nuova lettura annulla la precedente
  Completer<void>? _speech;
  Completer<void>? _segment;
  int _segmentEnd = 0;
  List<int> _starts = []; // posizione di ogni parola nel testo letto dalla voce
  Timer? _estimate;
  bool _gotProgress = false;
  final Map<String, String?> _voiceTag = {}; // lingua -> variante installata (es. ar-SA)
  StreamSubscription? _posSub, _doneSub;

  bool get _sample => widget.path == null;
  String get _src => _t?.lang.isNotEmpty == true ? _t!.lang : (_lang == 'auto' ? 'es' : _lang);
  String get _dst => _src == 'ar' ? 'it' : 'ar';
  List<String>? get _trs => _t?.translations[_dst];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _mode = ReadMode.values[(p.getInt('readMode') ?? 0).clamp(0, 2)];
      _slow = p.getBool('readSlow') ?? false;
    } catch (_) {}
    final t = _sample ? sampleTranscript() : await loadTranscript(widget.path!);
    _setupTts();
    _posSub = _player.onPositionChanged.listen(_onPos);
    _doneSub = _player.onPlayerComplete.listen((_) {
      if (_mode == ReadMode.original && mounted) setState(() => _playing = false);
      _segment?.complete();
    });
    if (!_sample) {
      try {
        await _player.setSource(DeviceFileSource(widget.path!));
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _t = t;
      _loading = false;
      _resetKeys();
    });
  }

  void _resetKeys() {
    _keys
      ..clear()
      ..addAll(List.generate(_t?.lines.length ?? 0, (_) => GlobalKey()));
  }

  void _setupTts() {
    void done() {
      _estimate?.cancel();
      final c = _speech;
      _speech = null;
      if (c != null && !c.isCompleted) c.complete();
    }

    _tts.setCompletionHandler(done);
    _tts.setCancelHandler(done);
    _tts.setErrorHandler((_) => done());
    _tts.setProgressHandler((text, start, end, word) {
      _gotProgress = true;
      _estimate?.cancel();
      var i = 0;
      for (var k = 0; k < _starts.length; k++) {
        if (_starts[k] <= start) i = k;
      }
      if (mounted && i != _word) setState(() => _word = i);
    });
  }

  @override
  void dispose() {
    _gen++;
    _estimate?.cancel();
    _posSub?.cancel();
    _doneSub?.cancel();
    _player.dispose();
    _tts.stop();
    super.dispose();
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  // ---------------- voce del telefono ----------------

  Future<bool> _voice(String lang) async {
    if (!_voiceTag.containsKey(lang)) {
      String? found;
      for (final l in lang == 'ar'
          ? ['ar-SA', 'ar-EG', 'ar-AE', 'ar-XA', 'ar']
          : lang == 'es'
              ? ['es-ES', 'es-MX', 'es-US', 'es']
              : [lang]) {
        try {
          if (await _tts.isLanguageAvailable(l) == true) {
            found = l;
            break;
          }
        } catch (_) {}
      }
      _voiceTag[lang] = found;
    }
    final tag = _voiceTag[lang];
    if (tag == null) return false;
    try {
      await _tts.setLanguage(tag);
    } catch (_) {}
    return true;
  }

  /// Legge [text] con la voce di [lang] e muove l'ombra sulle parole.
  Future<void> _say(String text, String lang, int gen) async {
    if (!await _voice(lang)) {
      _snack(tr('Manca la voce {} sul telefono: Impostazioni → Sintesi vocale → Google → Installa dati vocali.')
          .replaceFirst('{}', _nameOf(lang)));
      _gen++;
      if (mounted) setState(() => _playing = false);
      return;
    }
    if (gen != _gen) return;
    await _tts.setSpeechRate(_slow ? 0.33 : 0.48);
    // inizio di ogni parola nel testo
    final starts = <int>[];
    final re = RegExp(r'\S+');
    for (final m in re.allMatches(text)) {
      starts.add(m.start);
    }
    _starts = starts;
    if (mounted) setState(() => _word = 0);
    final c = Completer<void>();
    _speech = c;
    // se il motore vocale non dice a che parola è, stima il tempo
    _estimate?.cancel();
    if (!_gotProgress) {
      final cps = (lang == 'ar' ? 11.0 : 14.0) * (_slow ? 0.7 : 1.0);
      final t0 = DateTime.now();
      _estimate = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (_gotProgress) return _estimate?.cancel();
        final ch = DateTime.now().difference(t0).inMilliseconds / 1000 * cps;
        var i = 0;
        for (var k = 0; k < starts.length; k++) {
          if (starts[k] <= ch) i = k;
        }
        if (mounted && i != _word) setState(() => _word = i);
      });
    }
    await _tts.speak(text);
    await c.future.timeout(Duration(seconds: 8 + text.length ~/ 4), onTimeout: () {});
    _estimate?.cancel();
  }

  // ---------------- lettura ----------------

  void _onPos(Duration d) {
    final t = _t;
    if (t == null || !mounted || _sample) return;
    final ms = d.inMilliseconds;
    if (_segment != null && ms >= _segmentEnd) {
      final c = _segment!;
      _segment = null;
      _player.pause();
      if (!c.isCompleted) c.complete();
      return;
    }
    if (_mode == ReadMode.translation || (_mode == ReadMode.alternate && _phaseTr)) return;
    final i = lineAt(t.lines, ms);
    final w = i < 0 ? -1 : wordAt(t.lines[i], ms);
    if (i != _line || w != _word) {
      final changed = i != _line;
      setState(() {
        _line = i;
        _word = w;
        _phaseTr = false;
      });
      if (changed) _scrollTo(i);
    }
  }

  void _scrollTo(int i) {
    if (i < 0 || i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        alignment: 0.25, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  Future<void> _stopAll() async {
    _gen++;
    _estimate?.cancel();
    _segment = null;
    try {
      await _tts.stop();
    } catch (_) {}
    try {
      await _player.pause();
    } catch (_) {}
  }

  Future<void> _pause() async {
    await _stopAll();
    if (mounted) setState(() => _playing = false);
  }

  /// Parte dalla frase [i] (e, nell'originale, dalla parola [w]).
  Future<void> _playFrom(int i, [int w = 0]) async {
    final t = _t;
    if (t == null || t.lines.isEmpty) return;
    await _stopAll();
    final g = _gen;
    i = i.clamp(0, t.lines.length - 1);
    setState(() {
      _playing = true;
      _line = i;
      _word = w;
      _phaseTr = _mode == ReadMode.translation;
    });
    _scrollTo(i);

    // Originale con la voce vera della radio: un unico ascolto continuo
    if (_mode == ReadMode.original && !_sample) {
      final l = t.lines[i];
      final at = w > 0 && w < l.words.length ? l.words[w].s : l.s;
      await _player.setPlaybackRate(_slow ? 0.75 : 1.0);
      await _player.seek(Duration(milliseconds: at));
      await _player.resume();
      return;
    }

    for (var k = i; k < t.lines.length; k++) {
      if (g != _gen || !mounted) return;
      setState(() {
        _line = k;
        _word = 0;
      });
      _scrollTo(k);
      if (_mode != ReadMode.translation) {
        setState(() => _phaseTr = false);
        if (_sample) {
          await _say(t.lines[k].text, _src, g);
        } else {
          await _segmentPlay(t.lines[k], g);
        }
        if (g != _gen) return;
      }
      if (_mode != ReadMode.original) {
        final trs = _trs;
        if (trs != null && k < trs.length && trs[k].trim().isNotEmpty) {
          setState(() => _phaseTr = true);
          if (_mode == ReadMode.alternate) await Future.delayed(const Duration(milliseconds: 250));
          if (g != _gen) return;
          await _say(trs[k], _dst, g);
        }
        if (g != _gen) return;
        await Future.delayed(const Duration(milliseconds: 350));
      }
    }
    if (g == _gen && mounted) setState(() => _playing = false);
  }

  /// Suona solo la frase [l] della registrazione, poi si ferma.
  Future<void> _segmentPlay(TLine l, int g) async {
    final c = Completer<void>();
    _segmentEnd = l.e + 250;
    _segment = c;
    await _player.setPlaybackRate(_slow ? 0.75 : 1.0);
    await _player.seek(Duration(milliseconds: l.s));
    if (g != _gen) return;
    await _player.resume();
    await c.future.timeout(Duration(milliseconds: (l.e - l.s) * 2 + 4000), onTimeout: () {});
  }

  Future<void> _toggle() async {
    if (_playing) return _pause();
    if (_mode == ReadMode.original && !_sample && _line >= 0) {
      // riprende da dove era
      setState(() => _playing = true);
      await _player.setPlaybackRate(_slow ? 0.75 : 1.0);
      await _player.resume();
      return;
    }
    await _playFrom(_line < 0 ? 0 : _line);
  }

  Future<void> _setMode(ReadMode m) async {
    final wasPlaying = _playing;
    await _stopAll();
    setState(() {
      _mode = m;
      _playing = false;
      _phaseTr = m == ReadMode.translation;
      _word = -1;
    });
    try {
      (await SharedPreferences.getInstance()).setInt('readMode', m.index);
    } catch (_) {}
    if (wasPlaying) _playFrom(_line < 0 ? 0 : _line);
  }

  Future<void> _setSlow(bool v) async {
    setState(() => _slow = v);
    try {
      (await SharedPreferences.getInstance()).setBool('readSlow', v);
    } catch (_) {}
    if (_playing && _mode == ReadMode.original && !_sample) {
      await _player.setPlaybackRate(v ? 0.75 : 1.0);
    } else if (_playing) {
      _playFrom(_line);
    }
  }

  // ---------------- creazione del testo ----------------

  Future<void> _create() async {
    final path = widget.path;
    if (path == null) return;
    await _stopAll();
    setState(() {
      _working = true;
      _stage = tr('Preparo…');
      _progress = null;
    });
    try {
      final startMs = _startMin * 60000;
      final endMs = _lenMin == 0 ? 0 : startMs + _lenMin * 60000;
      final t = await _whisper.transcribe(path,
          quality: _quality,
          lang: _lang,
          startMs: startMs,
          endMs: endMs,
          onStage: (s, p) {
            if (mounted) {
              setState(() {
                _stage = tr(s);
                _progress = p;
              });
            }
          });
      if (t.lines.isEmpty) {
        _snack(tr('Non ho sentito parlato in questo pezzo. Prova un altro minuto.'));
        return;
      }
      if (t.lang.isEmpty) t.lang = await _detect(t.lines.map((l) => l.text).take(10).join(' ')) ?? 'es';
      await saveTranscript(path, t);
      setState(() {
        _t = t;
        _resetKeys();
      });
      await _translate();
    } catch (e) {
      _snack('${tr('Non riuscito')}: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> _detect(String text) async {
    final id = LanguageIdentifier(confidenceThreshold: 0.3);
    try {
      final c = await id.identifyLanguage(text);
      return c == 'und' ? null : c.split('-').first;
    } catch (_) {
      return null;
    } finally {
      id.close();
    }
  }

  Future<void> _translate() async {
    final t = _t;
    final path = widget.path;
    if (t == null || path == null) return;
    final src = _ml(t.lang), dst = _ml(_dst);
    if (src == null || dst == null) {
      _snack(tr('Traduzione non disponibile per questa lingua'));
      return;
    }
    setState(() {
      _working = true;
      _progress = null;
    });
    final mgr = OnDeviceTranslatorModelManager();
    try {
      for (final m in {src.bcpCode, dst.bcpCode}) {
        if (m == 'en') continue;
        if (!await mgr.isModelDownloaded(m)) {
          setState(() => _stage = tr('Scarico il dizionario {} (circa 30 MB, solo la prima volta)…')
              .replaceFirst('{}', _nameOf(m)));
          await mgr.downloadModel(m, isWifiRequired: false);
        }
      }
      final trl = OnDeviceTranslator(sourceLanguage: src, targetLanguage: dst);
      final out = <String>[];
      for (var i = 0; i < t.lines.length; i++) {
        if (!mounted) break;
        setState(() {
          _stage = '${tr('Traduco in')} ${_nameOf(_dst)}… ${i + 1}/${t.lines.length}';
          _progress = (i + 1) / t.lines.length;
        });
        out.add(await trl.translateText(t.lines[i].text));
      }
      await trl.close();
      t.translations[_dst] = out;
      await saveTranscript(path, t);
    } catch (e) {
      _snack('${tr('Traduzione non riuscita')}: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _editTranslation(int i) async {
    final t = _t;
    final trs = _trs;
    if (t == null || trs == null || i >= trs.length) return;
    final ctrl = TextEditingController(text: trs[i]);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Correggi la traduzione')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.lines[i].text, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLines: null,
              autofocus: true,
              textDirection: _dst == 'ar' ? TextDirection.rtl : TextDirection.ltr,
              style: const TextStyle(fontSize: 20),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annulla'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('Salva'))),
        ],
      ),
    );
    ctrl.dispose();
    if (res == null || res.isEmpty) return;
    setState(() => trs[i] = res);
    if (!_sample) await saveTranscript(widget.path!, t);
  }

  Future<void> _redo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Rifare il testo?')),
        content: Text(tr('Il testo e la traduzione di questa registrazione verranno cancellati. L\'audio resta.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annulla'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Rifai'))),
        ],
      ),
    );
    if (ok != true) return;
    await _stopAll();
    await deleteTranscript(widget.path!);
    setState(() {
      _t = null;
      _playing = false;
      _line = -1;
      _word = -1;
    });
  }

  // ---------------- interfaccia ----------------

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final hasText = t != null && t.lines.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Leggi e traduci'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            Text(widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          if (hasText)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'share') {
                  Share.share(t.toPlainText(_dst), subject: widget.name);
                }
                if (v == 'retr') _translate();
                if (v == 'redo') _redo();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: 'share',
                    child: ListTile(leading: const Icon(Icons.share), title: Text(tr('Condividi il testo')))),
                if (!_sample) ...[
                  PopupMenuItem(
                      value: 'retr',
                      child: ListTile(leading: const Icon(Icons.translate), title: Text(tr('Traduci di nuovo')))),
                  PopupMenuItem(
                      value: 'redo',
                      child: ListTile(
                          leading: const Icon(Icons.refresh), title: Text(tr('Rifai il testo (altro pezzo)')))),
                ],
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _working
              ? _workingView()
              : hasText
                  ? _readerView(t)
                  : _setupView(),
      bottomNavigationBar: hasText && !_working && !_loading ? _controls() : null,
    );
  }

  Widget _workingView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.menu_book_rounded, size: 56, color: accent),
              const SizedBox(height: 20),
              Text(_stage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress, minHeight: 6, borderRadius: BorderRadius.circular(3)),
              const SizedBox(height: 16),
              Text(tr('Tutto sul telefono, senza internet (tranne i download della prima volta).'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );

  Widget _setupView() {
    final s = Theme.of(context).colorScheme;
    final totalMin = widget.duration == null ? 240 : (widget.duration!.inSeconds / 60).ceil();
    final starts = <int>[0, 1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]
        .where((m) => m == 0 || m < totalMin)
        .toList();
    if (!starts.contains(_startMin)) _startMin = 0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Icon(Icons.menu_book_rounded, size: 52, color: accent),
        const SizedBox(height: 8),
        Text(tr('Trasforma la registrazione in un libro da leggere'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
            tr('Il telefono scrive quello che dice la radio, lo traduce in arabo e, mentre ascolti, un\'ombra passa sulle parole.'),
            textAlign: TextAlign.center,
            style: TextStyle(color: s.onSurfaceVariant)),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReaderPage.sample())),
          icon: const Text('🇪🇸 → 🇸🇦', style: TextStyle(fontSize: 18)),
          label: Text(tr('Vedi l\'esempio spagnolo → arabo')),
        ),
        const SizedBox(height: 22),
        Text(tr('Lingua della radio'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text('🌐 ${tr('Automatica')}'),
              selected: _lang == 'auto',
              onSelected: (_) => setState(() => _lang = 'auto'),
            ),
            for (final e in readerLangs.entries)
              ChoiceChip(
                label: Text('${e.value.$1} ${e.value.$2}'),
                selected: _lang == e.key,
                onSelected: (_) => setState(() => _lang = e.key),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(tr('Quale pezzo'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _startMin,
                decoration: InputDecoration(labelText: tr('Dal minuto'), border: const OutlineInputBorder()),
                items: [for (final m in starts) DropdownMenuItem(value: m, child: Text(fmtMs(m * 60000)))],
                onChanged: (v) => setState(() => _startMin = v ?? 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _lenMin,
                decoration: InputDecoration(labelText: tr('Durata'), border: const OutlineInputBorder()),
                items: [
                  for (final m in [2, 5, 10, 20, 30, 60])
                    DropdownMenuItem(value: m, child: Text('$m min')),
                  DropdownMenuItem(value: 0, child: Text(tr('Tutto'))),
                ],
                onChanged: (v) => setState(() => _lenMin = v ?? 5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(tr('Più è lungo, più tempo ci vuole: circa quanto la durata del pezzo.'),
            style: TextStyle(fontSize: 13, color: s.onSurfaceVariant)),
        const SizedBox(height: 20),
        Text(tr('Precisione'), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SegmentedButton<Quality>(
          segments: [
            for (final q in Quality.values)
              ButtonSegment(value: q, label: Text('${tr(q.label)}\n${q.size}', textAlign: TextAlign.center)),
          ],
          selected: {_quality},
          onSelectionChanged: (v) => setState(() => _quality = v.first),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: _create,
          icon: const Icon(Icons.auto_stories),
          label: Text(tr('Crea il testo e la traduzione araba'), style: const TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _readerView(Transcript t) {
    final s = Theme.of(context).colorScheme;
    final trs = _trs;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: SegmentedButton<ReadMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: ReadMode.original,
                  label: Text('${_flagOf(_src)} ${tr('Impara')}', maxLines: 1)),
              ButtonSegment(
                  value: ReadMode.translation, label: Text('${_flagOf(_dst)} ${_nameOf(_dst)}', maxLines: 1)),
              ButtonSegment(value: ReadMode.alternate, label: Text('🔁 ${tr('Alterna')}', maxLines: 1)),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => _setMode(v.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            switch (_mode) {
              ReadMode.original => _sample
                  ? tr('Leggi lo spagnolo seguendo l\'ombra (nell\'esempio legge la voce del telefono).')
                  : tr('La voce vera della radio: segui l\'ombra e impara a leggere.'),
              ReadMode.translation => tr('La traduzione letta dalla voce araba, parola per parola.'),
              ReadMode.alternate => tr('Ogni frase: prima l\'originale, poi la traduzione.'),
            },
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: s.onSurfaceVariant),
          ),
        ),
        if (trs == null && !_sample)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: FilledButton.tonalIcon(
                onPressed: _translate,
                icon: const Icon(Icons.translate),
                label: Text('${tr('Traduci in')} ${_nameOf(_dst)}')),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
            child: Column(
              children: [
                for (var i = 0; i < t.lines.length; i++)
                  _lineCard(t, i, trs != null && i < trs.length ? trs[i] : null),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _lineCard(Transcript t, int i, String? trText) {
    final s = Theme.of(context).colorScheme;
    final cur = i == _line;
    final l = t.lines[i];
    final srcRtl = _src == 'ar';
    final dstRtl = _dst == 'ar';
    final big = _mode == ReadMode.translation ? 'tr' : (_mode == ReadMode.original ? 'src' : 'both');

    final srcWords = l.words.map((w) => w.t).toList();
    final trWords = trText == null ? <String>[] : trText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final srcActive = cur && !_phaseTr && _mode != ReadMode.translation;
    final trActive = cur && (_phaseTr || _mode == ReadMode.translation);

    final srcBlock = _words(
      srcWords,
      active: srcActive ? _word : -1,
      size: big == 'src' ? 23 : (big == 'both' ? 20 : 15),
      dim: big == 'tr',
      rtl: srcRtl,
      onTap: (w) => _mode == ReadMode.translation ? _playFrom(i) : _playFrom(i, w),
    );
    final trBlock = trText == null
        ? null
        : _words(
            trWords,
            active: trActive ? _word : -1,
            size: big == 'tr' ? 26 : (big == 'both' ? 23 : 18),
            dim: big == 'src',
            rtl: dstRtl,
            onTap: (_) => _playFrom(i),
          );

    return AnimatedContainer(
      key: i < _keys.length ? _keys[i] : null,
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: cur ? s.surfaceContainerHigh : s.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cur ? accent.withValues(alpha: 0.6) : Colors.transparent, width: 1.5),
      ),
      child: InkWell(
        onLongPress: trText == null ? null : () => _editTranslation(i),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(_sample ? '${i + 1}' : fmtMs(l.s),
                    style: TextStyle(fontSize: 12, color: cur ? accent : s.onSurfaceVariant)),
                const Spacer(),
                if (cur && _playing)
                  Icon(Icons.graphic_eq, size: 16, color: accent.withValues(alpha: 0.9)),
              ],
            ),
            const SizedBox(height: 4),
            if (big == 'tr' && trBlock != null) ...[
              trBlock,
              const SizedBox(height: 8),
              srcBlock,
            ] else ...[
              srcBlock,
              if (trBlock != null) ...[
                Divider(height: 16, color: s.outlineVariant.withValues(alpha: 0.4)),
                trBlock,
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Le parole di una frase; [active] = parola sotto l'ombra.
  Widget _words(List<String> words,
      {required int active,
      required double size,
      required bool dim,
      required bool rtl,
      required void Function(int) onTap}) {
    final s = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          for (var k = 0; k < words.length; k++)
            GestureDetector(
              onTap: () => onTap(k),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: k == active ? accent.withValues(alpha: 0.30) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: k == active
                      ? [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: 1)]
                      : null,
                ),
                child: Text(
                  words[k],
                  style: TextStyle(
                    fontSize: size,
                    height: rtl ? 1.7 : 1.45,
                    fontWeight: k == active ? FontWeight.w700 : FontWeight.w400,
                    color: k == active
                        ? Colors.white
                        : (active >= 0 && k < active)
                            ? s.onSurface.withValues(alpha: dim ? 0.55 : 0.75)
                            : s.onSurface.withValues(alpha: dim ? 0.6 : 0.95),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controls() {
    final s = Theme.of(context).colorScheme;
    final n = _t?.lines.length ?? 0;
    return SafeArea(
      child: Container(
        color: s.surfaceContainer,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Row(
          children: [
            ChoiceChip(
              label: Text(_slow ? '🐢 ${tr('Lento')}' : '1×'),
              selected: _slow,
              onSelected: _setSlow,
            ),
            const Spacer(),
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.skip_previous_rounded),
              onPressed: () => _playFrom((_line < 0 ? 0 : _line) - 1),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              iconSize: 40,
              style: IconButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
              icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              onPressed: _toggle,
            ),
            const SizedBox(width: 4),
            IconButton(
              iconSize: 32,
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: () => _playFrom(((_line < 0 ? 0 : _line) + 1).clamp(0, n - 1)),
            ),
            const Spacer(),
            SizedBox(
              width: 64,
              child: Text(n == 0 ? '' : '${(_line < 0 ? 0 : _line) + 1}/$n',
                  textAlign: TextAlign.end, style: TextStyle(color: s.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

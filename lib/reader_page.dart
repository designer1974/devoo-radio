// «Leggi e traduci»: il testo della registrazione come un libro.
// Si sente solo la voce vera della radio; mentre parla, un'ombra passa sulle parole
// dell'originale e, insieme, sulla traduzione araba scritta.
//  · Impara:     testo originale grande (per imparare a leggere), arabo sotto.
//  · Traduzione: arabo grande, originale piccolo sopra.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart' show tr;
import 'text_job.dart';
import 'transcript.dart';
import 'whisper_service.dart';
import 'widgets.dart' show accent;

/// Lingue dell'audio che sappiamo trascrivere e tradurre.
const readerLangs = <String, (String, String)>{
  'es': ('🇪🇸', 'Español'),
  'ar': ('🇸🇦', 'العربية'),
  'it': ('🇮🇹', 'Italiano'),
  'en': ('🇬🇧', 'English'),
  'fr': ('🇫🇷', 'Français'),
  'de': ('🇩🇪', 'Deutsch'),
  'pt': ('🇵🇹', 'Português'),
  'nl': ('🇳🇱', 'Nederlands'),
  'tr': ('🇹🇷', 'Türkçe'),
  'ru': ('🇷🇺', 'Русский'),
  'uk': ('🇺🇦', 'Українська'),
  'pl': ('🇵🇱', 'Polski'),
  'ro': ('🇷🇴', 'Română'),
  'el': ('🇬🇷', 'Ελληνικά'),
  'sq': ('🇦🇱', 'Shqip'),
  'sv': ('🇸🇪', 'Svenska'),
  'fa': ('🇮🇷', 'فارسی'),
  'ur': ('🇵🇰', 'اردو'),
  'he': ('🇮🇱', 'עברית'),
  'hi': ('🇮🇳', 'हिन्दी'),
  'bn': ('🇧🇩', 'বাংলা'),
  'zh': ('🇨🇳', '中文'),
  'ja': ('🇯🇵', '日本語'),
  'ko': ('🇰🇷', '한국어'),
  'id': ('🇮🇩', 'Indonesia'),
};

bool _rtl(String code) => const {'ar', 'fa', 'ur', 'he'}.contains(code);

String _flagOf(String code) => readerLangs[code]?.$1 ?? '🌐';

/// 🇺🇸 per l'inglese di una radio americana, 🇬🇧 per una britannica, 🇲🇽 per lo spagnolo messicano…
String _flagFor(String code, String? radioFlag) =>
    radioFlag != null && guessLang(radioFlag) == code ? radioFlag : _flagOf(code);
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

enum ReadMode { original, translation }

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
  final _player = AudioPlayer();
  final _keys = <GlobalKey>[];
  final _endKey = GlobalKey();

  Transcript? _t;
  bool _loading = true;

  // creazione del testo
  bool _working = false;
  String _stage = '';
  double? _progress;
  late String _lang = guessLang(widget.flag);
  int _startMin = 0;
  late int _lenMin = (widget.duration?.inMinutes ?? 99) <= 15 ? 0 : 5; // 0 = tutto
  Quality _quality = Quality.balanced;

  // lettura
  ReadMode _mode = ReadMode.original;
  double _rate = 1.0; // velocità: 1, 0.75, 0.5
  int _sync = 300; // ms: l'ombra anticipa un po' (Whisper segna le parole in ritardo)
  // posizione stimata tra un aggiornamento e l'altro del player (che arriva ogni ~200 ms)
  int _basePos = 0;
  DateTime _baseAt = DateTime.now();
  Timer? _tick;
  bool _playing = false;
  int _line = -1;
  int _word = -1; // parola dell'originale sotto l'ombra
  int _trWord = -1; // parola della traduzione sotto l'ombra
  int _pos = 0; // ms
  Timer? _demo; // esempio: nessun audio, il tempo scorre da solo
  StreamSubscription? _posSub, _doneSub;

  bool get _sample => widget.path == null;
  String get _src => _t?.lang.isNotEmpty == true ? _t!.lang : (_lang == 'auto' ? 'es' : _lang);
  String _target = 'ar'; // lingua in cui tradurre (scelta da te)
  String get _dst => _sample ? 'ar' : TextJob.dstFor(_src, _target);
  List<String>? get _trs => _t?.translations[_dst];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final p = await SharedPreferences.getInstance();
      _mode = ReadMode.values[(p.getInt('readMode') ?? 0).clamp(0, ReadMode.values.length - 1)];
      _rate = p.getDouble('readRate') ?? 1.0;
      _sync = p.getInt('readSync') ?? 300;
      _target = p.getString('readTarget') ?? 'ar';
    } catch (_) {}
    final t = _sample ? sampleTranscript() : await loadTranscript(widget.path!);
    _posSub = _player.onPositionChanged.listen((d) {
      _basePos = d.inMilliseconds;
      _baseAt = DateTime.now();
      if (_tick == null) _onPos(_basePos + _sync);
    });
    _doneSub = _player.onPlayerComplete.listen((_) {
      _stopTick();
      if (mounted) setState(() => _playing = false);
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
    final running = _sample ? null : TextJob.of(widget.path!);
    if (running != null && (running.running || running.error != null || running.warning != null)) {
      _attach(running);
    } else {
      _checkInterrupted();
    }
  }

  void _resetKeys() {
    _keys
      ..clear()
      ..addAll(List.generate(_t?.lines.length ?? 0, (_) => GlobalKey()));
  }

  @override
  void dispose() {
    _job?.removeListener(_onJob);
    _demo?.cancel();
    _tick?.cancel();
    _posSub?.cancel();
    _doneSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  void _snack(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  // ---------------- lettura ----------------

  /// Parole della traduzione di una frase.
  List<String> _trWordsOf(int i) {
    final trs = _trs;
    if (trs == null || i < 0 || i >= trs.length) return const [];
    return trs[i].split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  }

  /// La traduzione non ha i tempi: l'ombra la percorre in proporzione
  /// a quanto la radio è avanti nella frase.
  int _trWordAt(int i, int ms) {
    final t = _t;
    final words = _trWordsOf(i);
    if (t == null || words.isEmpty) return -1;
    final l = t.lines[i];
    // pezzi tra le virgole: l'ombra resta nel pezzo che la radio sta dicendo
    final tc = t.chunks[_dst];
    var srcFrom = 0, srcTo = l.words.length, trFrom = 0, trTo = words.length;
    if (tc != null && i < tc.length && tc[i].length >= 2) {
      final c = tc[i];
      final sw = wordAt(l, ms).clamp(0, l.words.length - 1);
      var acc = 0;
      for (var k = 0; k + 1 < c.length; k += 2) {
        final start = c[k], n = c[k + 1];
        final next = k + 2 < c.length ? c[k + 2] : l.words.length;
        if (sw >= start && sw < next) {
          srcFrom = start;
          srcTo = next;
          trFrom = acc;
          trTo = (acc + n).clamp(acc, words.length);
          break;
        }
        acc += n;
      }
      if (trTo <= trFrom) return trFrom.clamp(0, words.length - 1);
    }
    final a = l.words[srcFrom.clamp(0, l.words.length - 1)].s;
    final b = srcTo < l.words.length ? l.words[srcTo].s : l.e;
    final span = (b - a).clamp(1, 1 << 30);
    final f = ((ms - a) / span).clamp(0.0, 0.999);
    final part = words.sublist(trFrom, trTo);
    final total = part.fold<int>(0, (x, w) => x + w.length + 1);
    final target = f * total;
    var acc2 = 0;
    for (var k = 0; k < part.length; k++) {
      acc2 += part[k].length + 1;
      if (acc2 > target) return trFrom + k;
    }
    return trTo - 1;
  }


  void _onPos(int ms) {
    final t = _t;
    if (t == null || !mounted) return;
    _pos = ms;
    // oltre la fine del testo: ferma la voce e mostra «Continua il testo»
    if (!_sample && _playing && t.lines.isNotEmpty && _hasMoreAudio(t) && ms - _sync > _textEnd(t) + 800) {
      _pause();
      if (_line != t.lines.length - 1 || _word != -1) {
        setState(() {
          _line = t.lines.length - 1;
          _word = -1;
          _trWord = -1;
        });
      }
      _snack(tr('Fine del testo. Premi «Continua il testo» per i minuti successivi.'));
      Future.delayed(const Duration(milliseconds: 300), () {
        final ctx = _endKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400));
      });
      return;
    }
    final i = lineAt(t.lines, ms);
    final w = i < 0 ? -1 : wordAt(t.lines[i], ms);
    final tw = i < 0 ? -1 : _trWordAt(i, ms);
    if (i != _line || w != _word || tw != _trWord) {
      final changed = i != _line;
      setState(() {
        _line = i;
        _word = w;
        _trWord = tw;
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

  void _startTick() {
    _tick?.cancel();
    _baseAt = DateTime.now();
    _tick = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_playing) return;
      final est = _basePos + (DateTime.now().difference(_baseAt).inMilliseconds * _rate).round();
      _onPos(est + _sync);
    });
  }

  void _stopTick() {
    _tick?.cancel();
    _tick = null;
  }

  Future<void> _pause() async {
    _demo?.cancel();
    _stopTick();
    try {
      await _player.pause();
    } catch (_) {}
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _resume() async {
    final t = _t;
    if (t == null || t.lines.isEmpty) return;
    setState(() => _playing = true);
    if (_sample) {
      _demo?.cancel();
      final end = t.lines.last.e + 300;
      var last = DateTime.now();
      _demo = Timer.periodic(const Duration(milliseconds: 50), (tm) {
        final now = DateTime.now();
        final step = now.difference(last).inMilliseconds * _rate;
        last = now;
        final ms = _pos + step.round();
        if (ms >= end) {
          tm.cancel();
          _onPos(end);
          if (mounted) setState(() => _playing = false);
          _pos = 0;
          return;
        }
        _onPos(ms);
      });
      return;
    }
    await _player.setPlaybackRate(_rate);
    await _player.resume();
    try {
      _basePos = (await _player.getCurrentPosition())?.inMilliseconds ?? _basePos;
    } catch (_) {}
    _startTick();
  }

  /// Va alla frase [i] (e alla parola [w]) e suona da lì.
  Future<void> _playFrom(int i, [int w = 0]) async {
    final t = _t;
    if (t == null || t.lines.isEmpty) return;
    i = i.clamp(0, t.lines.length - 1);
    final l = t.lines[i];
    final at = w > 0 && w < l.words.length ? l.words[w].s : l.s;
    if (_sample) {
      _onPos(at);
    } else {
      await _player.seek(Duration(milliseconds: at));
      _basePos = at;
      _baseAt = DateTime.now();
      _onPos(at);
    }
    await _resume();
  }

  Future<void> _toggle() async {
    if (_playing) return _pause();
    if (_line < 0) return _playFrom(0);
    await _resume();
  }

  Future<void> _setMode(ReadMode m) async {
    setState(() => _mode = m);
    _scrollTo(_line);
    try {
      (await SharedPreferences.getInstance()).setInt('readMode', m.index);
    } catch (_) {}
  }

  Future<void> _nextRate() async {
    const rates = [1.0, 0.75, 0.5];
    final i = rates.indexOf(_rate);
    final v = rates[(i + 1) % rates.length];
    // la posizione stimata riparte da qui con la nuova velocità
    _basePos = _basePos + (DateTime.now().difference(_baseAt).inMilliseconds * _rate).round();
    _baseAt = DateTime.now();
    setState(() => _rate = v);
    try {
      (await SharedPreferences.getInstance()).setDouble('readRate', v);
    } catch (_) {}
    if (_playing && !_sample) await _player.setPlaybackRate(v);
  }

  Future<void> _setTarget(String code, {bool translateNow = true}) async {
    setState(() => _target = code);
    try {
      (await SharedPreferences.getInstance()).setString('readTarget', code);
    } catch (_) {}
    if (translateNow && !_sample && _t != null && _t!.translations[_dst] == null) _translate();
  }

  int _textEnd(Transcript t) => t.to > 0 ? t.to : t.lines.last.e;

  bool _hasMoreAudio(Transcript t) {
    final d = widget.duration?.inMilliseconds ?? 0;
    return t.to > 0 && (d == 0 || d - t.to > 3000);
  }

  Future<void> _extend(int minutes) async {
    final path = widget.path;
    if (path == null) return;
    await _pause();
    _attach(TextJob.extend(path, quality: _quality, minutes: minutes, target: _target));
  }

  Widget _endCard(Transcript t) {
    final s = Theme.of(context).colorScheme;
    final d = widget.duration;
    return Container(
      key: _endKey,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: s.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(
              '${tr('Il testo arriva fino a')} ${fmtMs(_textEnd(t))}'
              '${d == null ? '' : ' ${tr('di')} ${fmtMs(d.inMilliseconds)}'}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                  onPressed: () => _extend(5),
                  icon: const Icon(Icons.auto_stories),
                  label: Text('${tr('Continua il testo')} (5 min)')),
              OutlinedButton(onPressed: () => _extend(15), child: const Text('+15 min')),
              OutlinedButton(onPressed: () => _extend(60), child: const Text('+60 min')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickTarget() async {
    final code = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(tr('Traduci in'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              for (final e in readerLangs.entries)
                if (e.key != _src)
                  ListTile(
                    leading: Text(e.value.$1, style: const TextStyle(fontSize: 26)),
                    title: Text(e.value.$2),
                    trailing: e.key == _dst
                        ? const Icon(Icons.check, color: accent)
                        : (_t?.translations[e.key] != null ? const Icon(Icons.done_all, size: 18) : null),
                    onTap: () => Navigator.pop(ctx, e.key),
                  ),
            ],
          ),
        ),
      ),
    );
    if (code != null) await _setTarget(code);
  }

  Future<void> _setSync(int v) async {
    setState(() => _sync = v.clamp(-1000, 1500));
    try {
      (await SharedPreferences.getInstance()).setInt('readSync', _sync);
    } catch (_) {}
  }

  /// Regola a mano l'ombra rispetto alla voce.
  Future<void> _syncDialog() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Ombra e voce insieme'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(tr('Se la voce va avanti, premi «Ombra prima». Se l\'ombra corre troppo, premi «Ombra dopo».'),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.tonal(
                      onPressed: () {
                        _setSync(_sync - 100);
                        set(() {});
                      },
                      child: Text('◀ ${tr('Ombra dopo')}')),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Text('${_sync >= 0 ? '+' : ''}${(_sync / 1000).toStringAsFixed(1)} s',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                  FilledButton.tonal(
                      onPressed: () {
                        _setSync(_sync + 100);
                        set(() {});
                      },
                      child: Text('${tr('Ombra prima')} ▶')),
                ],
              ),
              const SizedBox(height: 8),
              TextButton(
                  onPressed: () {
                    _setSync(300);
                    set(() {});
                  },
                  child: Text(tr('Ripristina'))),
            ],
          ),
        ),
      ),
    );
  }


  // ---------------- creazione del testo ----------------

  String get _jobKey => 'readerJob|${widget.path?.split('/').last}';

  Future<void> _markStage(String? stage) async {
    try {
      final p = await SharedPreferences.getInstance();
      if (stage == null) {
        await p.remove(_jobKey);
      } else {
        await p.setString(_jobKey, stage);
      }
    } catch (_) {}
  }

  /// Se l'ultima volta il lavoro si è interrotto (app chiusa dal telefono), lo dice.
  Future<void> _checkInterrupted() async {
    if (_sample || _t != null) return;
    String? stage;
    try {
      stage = (await SharedPreferences.getInstance()).getString(_jobKey);
    } catch (_) {}
    if (stage == null || !mounted) return;
    await _markStage(null);
    _showError('${tr('L\'ultima volta il lavoro si è interrotto durante')}: «$stage».\n\n'
        '${tr('Di solito succede quando lo schermo si spegne e il telefono chiude l\'app. Ora lo schermo resta acceso da solo: riprova e non uscire dall\'app finché non ha finito.')}');
  }

  TextJob? _job;

  /// Si collega al lavoro in corso per questo file (anche se era partito prima).
  void _attach(TextJob j) {
    _job?.removeListener(_onJob);
    _job = j;
    j.addListener(_onJob);
    _onJob();
  }

  Future<void> _onJob() async {
    final j = _job;
    if (j == null || !mounted) return;
    if (j.running) {
      setState(() {
        _working = true;
        _stage = j.stage;
        _progress = j.progress;
      });
      return;
    }
    // finito: rilegge il testo salvato
    j.removeListener(_onJob);
    _job = null;
    final t = await loadTranscript(widget.path!);
    if (!mounted) return;
    setState(() {
      _working = false;
      if (t != null) {
        _t = t;
        _resetKeys();
      }
    });
    if (j.error != null) {
      final e = j.error!;
      j.error = null;
      _showError(e);
    } else if (j.warning != null) {
      _snack(j.warning!);
      j.warning = null;
    }
  }

  Future<void> _create() async {
    final path = widget.path;
    if (path == null) return;
    await _pause();
    final startMs = _startMin * 60000;
    final endMs = _lenMin == 0 ? 0 : startMs + _lenMin * 60000;
    _attach(TextJob.create(path, quality: _quality, lang: _lang, startMs: startMs, endMs: endMs, target: _target));
  }

  void _showError(String e) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Testo non creato')),
        content: SingleChildScrollView(
          child: Text('${tr('Qualcosa è andato storto. Mandami una foto di questo messaggio.')}\n\n$e'),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _translate() async {
    final path = widget.path;
    if (path == null) return;
    await _pause();
    _attach(TextJob.translate(path, _target));
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
              textDirection: _rtl(_dst) ? TextDirection.rtl : TextDirection.ltr,
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
    await _pause();
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _snack(tr('Aspetta che finisca, poi potrai uscire.'));
      },
      child: Scaffold(
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
    ),
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
              Text(tr('Puoi uscire da questa pagina: il lavoro continua. Resta però dentro l\'app (lo schermo resta acceso da solo).'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );

  Widget _langBox(String label, String flag, String name) {
    final s = Theme.of(context).colorScheme;
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(color: s.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: s.onSurfaceVariant)),
          Text(flag, style: const TextStyle(fontSize: 30)),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _setupView() {
    final s = Theme.of(context).colorScheme;
    final totalMin = widget.duration == null ? 240 : (widget.duration!.inSeconds / 60).ceil();
    final starts = <int>[0, 1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240]
        .where((m) => m == 0 || m < totalMin)
        .toList();
    if (!starts.contains(_startMin)) _startMin = 0;
    final partText = _lenMin == 0
        ? (widget.duration == null ? tr('tutta la registrazione') : '${tr('tutta la registrazione')} (${fmtMs(widget.duration!.inMilliseconds)})')
        : '${fmtMs(_startMin * 60000)} → ${fmtMs((_startMin + _lenMin) * 60000)}';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        const Icon(Icons.menu_book_rounded, size: 48, color: accent),
        const SizedBox(height: 6),
        Text(tr('Crea il testo di questa registrazione'),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(
            '${tr('Il telefono scrive quello che dice la radio e lo traduce in')} ${_nameOf(_target)}. ${tr('Poi ascolti la voce della radio e il colore segue le parole.')}',
            textAlign: TextAlign.center,
            style: TextStyle(color: s.onSurfaceVariant)),
        const SizedBox(height: 18),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
          onPressed: _create,
          icon: const Icon(Icons.auto_stories, size: 26),
          label: Text('${tr('Crea il testo e la traduzione')} ${_flagOf(_target)}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 8),
        const SizedBox(height: 4),
        // le due lingue, ben visibili: da quale a quale
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _langBox(tr('Radio'), _lang == 'auto' ? '🌐' : _flagFor(_lang, widget.flag),
                _lang == 'auto' ? tr('Automatica') : _nameOf(_lang)),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_forward_rounded, size: 28, color: accent),
            ),
            _langBox(tr('Traduzione'), _flagOf(_target), _nameOf(_target)),
          ],
        ),
        const SizedBox(height: 6),
        Text('$partText · ${tr(_quality.label)}',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: s.onSurfaceVariant)),
        const SizedBox(height: 22),
        Text('1. ${tr('Lingua della radio (quella che si sente)')}', style: const TextStyle(fontWeight: FontWeight.w700)),
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
                label: Text('${_flagFor(e.key, widget.flag)} ${e.value.$2}'),
                selected: _lang == e.key,
                onSelected: (_) => setState(() => _lang = e.key),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('2. ${tr('Traduci in (la lingua che vuoi leggere)')}', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in readerLangs.entries)
              ChoiceChip(
                label: Text('${e.value.$1} ${e.value.$2}'),
                selected: _target == e.key,
                onSelected: (_) => _setTarget(e.key, translateNow: false),
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
        Text(tr('Ci vuole circa quanto la durata del pezzo. La prima volta scarica anche il modello (una sola volta).'),
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
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReaderPage.sample())),
          child: Text(tr('Solo per vedere come funziona: esempio finto senza audio')),
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
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<ReadMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                  value: ReadMode.original,
                  label: Text('${_flagFor(_src, widget.flag)} ${tr('Impara')}', maxLines: 1)),
              ButtonSegment(
                  value: ReadMode.translation, label: Text('${_flagOf(_dst)} ${_nameOf(_dst)}', maxLines: 1)),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => _setMode(v.first),
                ),
              ),
              if (!_sample)
                IconButton(
                  tooltip: tr('Traduci in'),
                  icon: const Icon(Icons.translate),
                  onPressed: _pickTarget,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            switch (_mode) {
              ReadMode.original => _sample
                  ? tr('Esempio senza audio: premi ▶ e guarda l\'ombra passare sulle parole.')
                  : tr('Segui l\'ombra sul testo originale e impara a leggere.'),
              ReadMode.translation => tr('Segui l\'ombra sulla traduzione mentre parla la radio.'),
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
                if (!_sample && _hasMoreAudio(t)) _endCard(t),
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
    final srcRtl = _rtl(_src);
    final dstRtl = _rtl(_dst);
    final big = _mode == ReadMode.translation ? 'tr' : 'src';

    final srcWords = l.words.map((w) => w.t).toList();
    final trWords = trText == null ? <String>[] : trText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    final srcBlock = _words(
      srcWords,
      active: cur ? _word : -1,
      size: big == 'src' ? 23 : (big == 'both' ? 20 : 15),
      dim: big == 'tr',
      rtl: srcRtl,
      onTap: (w) => _playFrom(i, w),
    );
    final trBlock = trText == null
        ? null
        : _words(
            trWords,
            active: cur ? _trWord : -1,
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
                duration: const Duration(milliseconds: 70),
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
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  backgroundColor: _rate < 1 ? accent.withValues(alpha: 0.35) : null),
              onPressed: _nextRate,
              child: Text(
                  _rate == 1.0 ? '🐇 1×' : (_rate == 0.75 ? '🐢 0,75×' : '🐌 0,5×'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: tr('Ombra e voce insieme'),
              icon: const Icon(Icons.tune),
              onPressed: _syncDialog,
            ),
            const Spacer(),
            IconButton(
              iconSize: 30,
              visualDensity: VisualDensity.compact,
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
              iconSize: 30,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.skip_next_rounded),
              onPressed: () => _playFrom(((_line < 0 ? 0 : _line) + 1).clamp(0, n - 1)),
            ),
            const Spacer(),
            SizedBox(
              width: 40,
              child: Text(n == 0 ? '' : '${(_line < 0 ? 0 : _line) + 1}/$n',
                  textAlign: TextAlign.end, style: TextStyle(fontSize: 12, color: s.onSurfaceVariant)),
            ),
          ],
        ),
      ),
    );
  }
}

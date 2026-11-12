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
import 'transcript.dart';
import 'translate_online.dart';
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
  final _whisper = WhisperService();
  final _player = AudioPlayer();
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
  int _word = -1; // parola dell'originale sotto l'ombra
  int _trWord = -1; // parola della traduzione sotto l'ombra
  int _pos = 0; // ms
  Timer? _demo; // esempio: nessun audio, il tempo scorre da solo
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
      _mode = ReadMode.values[(p.getInt('readMode') ?? 0).clamp(0, ReadMode.values.length - 1)];
      _slow = p.getBool('readSlow') ?? false;
    } catch (_) {}
    final t = _sample ? sampleTranscript() : await loadTranscript(widget.path!);
    _posSub = _player.onPositionChanged.listen((d) => _onPos(d.inMilliseconds));
    _doneSub = _player.onPlayerComplete.listen((_) {
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
  }

  void _resetKeys() {
    _keys
      ..clear()
      ..addAll(List.generate(_t?.lines.length ?? 0, (_) => GlobalKey()));
  }

  @override
  void dispose() {
    _demo?.cancel();
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
    final span = (l.e - l.s).clamp(1, 1 << 30);
    final f = ((ms - l.s) / span).clamp(0.0, 0.999);
    final total = words.fold<int>(0, (a, w) => a + w.length + 1);
    final target = f * total;
    var acc = 0;
    for (var k = 0; k < words.length; k++) {
      acc += words[k].length + 1;
      if (acc > target) return k;
    }
    return words.length - 1;
  }

  void _onPos(int ms) {
    final t = _t;
    if (t == null || !mounted) return;
    _pos = ms;
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

  Future<void> _pause() async {
    _demo?.cancel();
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
        final step = now.difference(last).inMilliseconds * (_slow ? 0.75 : 1.0);
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
    await _player.setPlaybackRate(_slow ? 0.75 : 1.0);
    await _player.resume();
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

  Future<void> _setSlow(bool v) async {
    setState(() => _slow = v);
    try {
      (await SharedPreferences.getInstance()).setBool('readSlow', v);
    } catch (_) {}
    if (_playing && !_sample) await _player.setPlaybackRate(v ? 0.75 : 1.0);
  }

  // ---------------- creazione del testo ----------------

  Future<void> _create() async {
    final path = widget.path;
    if (path == null) return;
    await _pause();
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
      if (t.lang.isEmpty) t.lang = await OnlineTranslator.detect(t.lines.map((l) => l.text).take(10).join(' ')) ?? 'es';
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

  Future<void> _translate() async {
    final t = _t;
    final path = widget.path;
    if (t == null || path == null) return;
    final dst = _dst;
    setState(() {
      _working = true;
      _progress = 0;
      _stage = '${tr('Traduco in')} ${_nameOf(dst)}…';
    });
    try {
      final out = await OnlineTranslator.lines(t.lines.map((l) => l.text).toList(), t.lang, dst,
          progress: (n) {
        if (mounted) {
          setState(() {
            _stage = '${tr('Traduco in')} ${_nameOf(dst)}… $n/${t.lines.length}';
            _progress = n / t.lines.length;
          });
        }
      });
      t.translations[dst] = out;
      await saveTranscript(path, t);
    } catch (_) {
      _snack(tr('Traduzione non riuscita: serve internet. Riprova con ⋮ → Traduci di nuovo.'));
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

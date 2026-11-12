// Testo di una registrazione: frasi e parole con i tempi, più le traduzioni.
// Si salva in una cartella separata (non in quella delle registrazioni),
// così non compare nell'elenco e non tocca i file audio.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

class TWord {
  final int s, e; // millisecondi nella registrazione
  final String t;
  const TWord(this.s, this.e, this.t);
  Map<String, dynamic> toJson() => {'s': s, 'e': e, 't': t};
  factory TWord.fromJson(Map<String, dynamic> j) =>
      TWord((j['s'] as num).toInt(), (j['e'] as num).toInt(), j['t'] as String);
}

class TLine {
  final List<TWord> words;
  const TLine(this.words);
  int get s => words.first.s;
  int get e => words.last.e;
  String get text => words.map((w) => w.t).join(' ');
  Map<String, dynamic> toJson() => {'w': words.map((w) => w.toJson()).toList()};
  factory TLine.fromJson(Map<String, dynamic> j) =>
      TLine((j['w'] as List).map((x) => TWord.fromJson(x as Map<String, dynamic>)).toList());
}

class Transcript {
  String lang; // lingua dell'audio, es. "es"
  final String model;
  final List<TLine> lines;
  final Map<String, List<String>> translations; // lingua -> una traduzione per frase
  final int from, to; // pezzo trascritto (ms); to = 0 fino alla fine
  Transcript(this.lang, this.model, this.lines,
      {Map<String, List<String>>? tr, this.from = 0, this.to = 0})
      : translations = tr ?? {};

  Map<String, dynamic> toJson() => {
        'v': 1,
        'lang': lang,
        'model': model,
        'from': from,
        'to': to,
        'lines': lines.map((l) => l.toJson()).toList(),
        'tr': translations,
      };

  factory Transcript.fromJson(Map<String, dynamic> j) => Transcript(
        j['lang'] as String? ?? '',
        j['model'] as String? ?? '',
        (j['lines'] as List).map((x) => TLine.fromJson(x as Map<String, dynamic>)).toList(),
        tr: ((j['tr'] as Map?) ?? {})
            .map((k, v) => MapEntry(k as String, (v as List).map((e) => '$e').toList())),
        from: (j['from'] as num?)?.toInt() ?? 0,
        to: (j['to'] as num?)?.toInt() ?? 0,
      );

  /// Testo da condividere: originale e traduzione frase per frase.
  String toPlainText([String? trLang]) {
    final b = StringBuffer();
    final tr = trLang == null ? null : translations[trLang];
    for (var i = 0; i < lines.length; i++) {
      b.writeln('[${fmtMs(lines[i].s)}] ${lines[i].text}');
      if (tr != null && i < tr.length) b.writeln(tr[i]);
      b.writeln();
    }
    return b.toString();
  }
}

String fmtMs(int ms) {
  final h = ms ~/ 3600000, m = (ms ~/ 60000) % 60, s = (ms ~/ 1000) % 60;
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

// ---------------- file dei testi ----------------

Directory? _dir;

Future<Directory> _textsDir() async {
  final d = _dir ?? Directory('${(await getApplicationSupportDirectory()).path}/texts');
  if (!d.existsSync()) d.createSync(recursive: true);
  return _dir = d;
}

String _key(String audioPath) => audioPath.split('/').last;

Future<File> _fileFor(String audioPath) async =>
    File('${(await _textsDir()).path}/${_key(audioPath)}.json');

Future<Transcript?> loadTranscript(String audioPath) async {
  final f = await _fileFor(audioPath);
  if (!f.existsSync()) return null;
  try {
    return Transcript.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

Future<void> saveTranscript(String audioPath, Transcript t) async =>
    (await _fileFor(audioPath)).writeAsStringSync(jsonEncode(t.toJson()));

Future<bool> hasTranscript(String audioPath) async => (await _fileFor(audioPath)).existsSync();

/// Il testo segue la registrazione quando la rinomini.
Future<void> moveTranscript(String fromAudio, String toAudio) async {
  try {
    final f = await _fileFor(fromAudio);
    if (f.existsSync()) f.renameSync((await _fileFor(toAudio)).path);
  } catch (_) {}
}

Future<void> deleteTranscript(String audioPath) async {
  try {
    final f = await _fileFor(audioPath);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}

// ---------------- parole → frasi ----------------

/// Un pezzo restituito da Whisper (una parola o una frase).
class RawSeg {
  final int s, e;
  final String text;
  const RawSeg(this.s, this.e, this.text);
}

final _noise = RegExp(r'^[\[\(♪*].*[\]\)♪*]$');
final _endSentence = RegExp(r'[.!?…。؟!]["»”)]*$');

/// Trasforma i pezzi di Whisper in frasi con parole e tempi.
List<TLine> buildLines(List<RawSeg> segs) {
  final words = <TWord>[];
  for (final g in segs) {
    final t = g.text.trim();
    if (t.isEmpty || _noise.hasMatch(t)) continue;
    final parts = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.length == 1) {
      // Whisper a volte stacca la punteggiatura: la riattacca alla parola prima
      if (words.isNotEmpty && RegExp(r'^[.,;:!?¡¿…»”)]+$').hasMatch(parts.first)) {
        final p = words.removeLast();
        words.add(TWord(p.s, max(p.e, g.e), '${p.t}${parts.first}'));
        continue;
      }
      words.add(TWord(g.s, max(g.s, g.e), parts.first));
      continue;
    }
    final total = parts.fold<int>(0, (a, w) => a + w.length + 1);
    var pos = 0;
    final dur = max(0, g.e - g.s);
    for (final w in parts) {
      final a = g.s + (dur * pos / total).round();
      pos += w.length + 1;
      final b = g.s + (dur * pos / total).round();
      words.add(TWord(a, b, w));
    }
  }
  final lines = <TLine>[];
  var cur = <TWord>[];
  for (final w in words) {
    if (cur.isNotEmpty) {
      final gap = w.s - cur.last.e;
      final len = cur.last.e - cur.first.s;
      if (gap > 1500 || len > 12000) {
        lines.add(TLine(cur));
        cur = [];
      }
    }
    cur.add(w);
    final len = w.e - cur.first.s;
    if (_endSentence.hasMatch(w.t) || (len > 7000 && w.t.endsWith(',')) || cur.length >= 30) {
      lines.add(TLine(cur));
      cur = [];
    }
  }
  if (cur.isNotEmpty) lines.add(TLine(cur));
  return lines;
}

/// Indice della frase in corso al tempo [ms].
int lineAt(List<TLine> lines, int ms) {
  if (lines.isEmpty) return -1;
  var lo = 0, hi = lines.length - 1, ans = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].s <= ms) {
      ans = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return ans;
}

/// Indice della parola in corso nella frase.
int wordAt(TLine l, int ms) {
  var ans = -1;
  for (var i = 0; i < l.words.length; i++) {
    if (l.words[i].s <= ms) ans = i;
  }
  return ans;
}

// ---------------- esempio ----------------

/// Testo di esempio: notiziario spagnolo con la traduzione araba (fuṣḥā).
/// I tempi servono solo all'ordine: l'esempio si legge con la voce del telefono.
Transcript sampleTranscript() {
  const es = [
    'Buenos días, son las ocho de la mañana y esto es el informativo de la radio.',
    'Hoy en Madrid hace sol, con una temperatura de dieciocho grados.',
    'El tráfico es intenso en la entrada de la ciudad por la autopista del sur.',
    'El ayuntamiento abre esta semana una nueva biblioteca en el barrio de Lavapiés.',
    'Los niños podrán leer libros gratis todas las tardes.',
    'Y ahora, la música: les dejamos con una canción muy especial.',
  ];
  const ar = [
    'صباحُ الخير، الساعةُ الآن الثامنةُ صباحًا، وهذه نشرةُ الأخبار من الإذاعة.',
    'الطقسُ اليومَ في مدريد مشمس، ودرجةُ الحرارة ثماني عشرةَ درجة.',
    'حركةُ المرور كثيفةٌ عند مدخل المدينة على الطريق السريع الجنوبي.',
    'تفتتحُ البلديةُ هذا الأسبوعَ مكتبةً جديدةً في حيّ لابابييس.',
    'سيتمكّنُ الأطفالُ من قراءة الكتب مجانًا كلَّ مساء.',
    'والآن مع الموسيقى: نترككم مع أغنيةٍ مميّزةٍ جدًّا.',
  ];
  var ms = 0;
  final lines = <TLine>[];
  for (final l in es) {
    final ws = <TWord>[];
    for (final w in l.split(' ')) {
      final d = 120 + w.length * 70;
      ws.add(TWord(ms, ms + d, w));
      ms += d;
    }
    lines.add(TLine(ws));
    ms += 600;
  }
  return Transcript('es', 'sample', lines, tr: {'ar': ar.toList()});
}

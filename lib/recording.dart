import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'flags.dart' show leadingFlag, stripFlag;
import 'models.dart';
import 'player.dart';
import 'recorder.dart';
import 'pro.dart';
import 'schedule.dart';
import 'rec_notice.dart';

String two(int n) => n.toString().padLeft(2, '0');

String fmtDur(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String fmtSize(int b) => b >= 1024 * 1024
    ? '${(b / 1024 / 1024).toStringAsFixed(1)} MB'
    : '${(b / 1024).toStringAsFixed(0)} KB';

String fmtDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';

/// Nome di file sicuro (niente / : * ? ecc.)
String cleanName(String s) =>
    s.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Una registrazione salvata.
class RecFile {
  final File file;
  final String name; // nome completo, con bandiera
  final String? flag;
  final String title;
  final DateTime date;
  final int size;
  Duration? duration;

  RecFile(this.file, this.name, this.flag, this.title, this.date, this.size);

  String get ext => file.path.split('.').last;
}

/// Elenco delle registrazioni nella cartella dell'app.
class Recordings extends ChangeNotifier {
  Recordings._();
  static final i = Recordings._();

  List<RecFile> items = [];
  Directory? _dir;

  Future<Directory> dir() async {
    final d = _dir ?? Directory('${(await getApplicationDocumentsDirectory()).path}/recordings');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  Future<void> reload() async {
    try {
      final d = await dir();
      final list = <RecFile>[];
      for (final e in d.listSync()) {
        if (e is! File) continue;
        final base = e.path.split('/').last;
        if (base.startsWith('.')) continue; // file temporanei
        final dot = base.lastIndexOf('.');
        if (dot <= 0) continue;
        final name = base.substring(0, dot);
        final st = e.statSync();
        list.add(RecFile(e, name, leadingFlag(name), stripFlag(name), st.modified, st.size));
      }
      list.sort((a, b) => b.date.compareTo(a.date));
      // tiene le durate già lette
      final old = {for (final r in items) r.file.path: r.duration};
      for (final r in list) {
        r.duration = old[r.file.path];
      }
      items = list;
      notifyListeners();
      for (final r in list.where((r) => r.duration == null)) {
        try {
          r.duration = Duration(milliseconds: await Recorder.durationMs(r.file.path));
        } catch (_) {
          r.duration = Duration.zero;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<String> uniquePath(String name, String ext, {String? except}) async {
    final d = await dir();
    var base = cleanName(name);
    if (base.isEmpty) base = 'Registrazione';
    var p = '${d.path}/$base.$ext';
    var n = 2;
    while (p != except && File(p).existsSync()) {
      p = '${d.path}/$base ($n).$ext';
      n++;
    }
    return p;
  }
}

/// Registrazione della radio in ascolto (direttamente dallo stream).
class RecController extends ChangeNotifier {
  RecController._() {
    RadioPlayer.i.addListener(_onPlayer);
    // registrazioni programmate: le segue anche se partono ad app chiusa
    _watch = Timer.periodic(const Duration(seconds: 1), (_) => _watchNative());
    // la radio non risponde: niente registrazione in attesa
    RadioPlayer.i.errors.listen((_) {
      if (_pending != null) {
        _pending = null;
        notifyListeners();
      }
    });
  }
  static final i = RecController._();

  Station? station;
  DateTime? startedAt;
  int bytes = 0;
  double? saving; // avanzamento del salvataggio 0..1
  Timer? _poll;

  final _messages = StreamController<String>.broadcast();
  Stream<String> get messages => _messages.stream;

  bool get recording => station != null && saving == null;

  // ---- registrazione programmata in corso (fatta dal servizio Android) ----
  Timer? _watch;
  String? extId;
  String extName = '';
  String extFlag = '';
  String extUrl = '';
  DateTime? extStart;
  DateTime? extEnd;
  int extBytes = 0;
  bool extStopping = false;

  bool get external => extId != null;

  /// C'è una registrazione qualsiasi (manuale o programmata).
  bool get busy => station != null || external;
  bool extSaving = false; // il servizio sta chiudendo il file
  bool get anyRecording => recording || (external && !extStopping && !extSaving);
  bool get anySaving => saving != null || extStopping || extSaving;

  String get recName => station?.name ?? '${extFlag.isEmpty ? '' : '$extFlag '}$extName';
  int get recBytes => station != null ? bytes : extBytes;

  Duration get elapsed {
    final st = startedAt ?? extStart;
    return st == null ? Duration.zero : DateTime.now().difference(st);
  }

  bool isRecording(Station s) => station?.id == s.id || (external && extUrl.isNotEmpty && s.url == extUrl);

  /// Ferma quella in corso, manuale o programmata.
  Future<void> stopAny() async {
    if (recording) return stopAndSave();
    if (!external || extStopping) return;
    extStopping = true;
    notifyListeners();
    await Schedules.i.stopRunning();
  }

  Future<void> _watchNative() async {
    if (station != null) return; // la manuale si controlla da sola
    try {
      final st = await Recorder.streamStatus();
      final id = st['schedId'] as String?;
      final busyNative = st['busy'] == true;
      if (id != null && busyNative) {
        final first = extId != id;
        extId = id;
        extName = (st['schedName'] as String?) ?? '';
        extFlag = (st['schedFlag'] as String?) ?? '';
        extUrl = (st['url'] as String?) ?? '';
        final t = (st['startedAt'] as num?)?.toInt() ?? 0;
        extStart = t > 0 ? DateTime.fromMillisecondsSinceEpoch(t) : DateTime.now();
        final e = (st['schedEnd'] as num?)?.toInt() ?? 0;
        extEnd = e > 0 ? DateTime.fromMillisecondsSinceEpoch(e) : null;
        extBytes = (st['bytes'] as num?)?.toInt() ?? 0;
        extSaving = st['running'] == false;
        if (first) unawaited(Schedules.i.reload());
        notifyListeners();
        // sicurezza: ora di fine passata ma ancora attiva -> si ferma
        final end = extEnd;
        if (end != null && !extStopping && !extSaving &&
            DateTime.now().isAfter(end.add(const Duration(seconds: 8)))) {
          unawaited(stopAny());
        }
      } else if (extId != null) {
        // finita (orario raggiunto o fermata): il file è pronto
        extId = null;
        extStopping = false;
        extSaving = false;
        extBytes = 0;
        notifyListeners();
        _messages.add('Registrazione programmata salvata in Registrate');
        unawaited(Recordings.i.reload());
        unawaited(Schedules.i.reload());
      }
    } catch (_) {}
  }

  Station? _pending; // radio da registrare appena parte

  /// Accende la radio (se serve) e registra appena è in onda.
  void recordStation(Station s) {
    if (busy) return;
    final p = RadioPlayer.i;
    if (p.isCurrent(s) && p.isPlaying && !p.isBuffering) {
      start();
      return;
    }
    _pending = s;
    notifyListeners();
    if (!p.isCurrent(s) || !p.wantsPlay) p.play(s);
  }

  bool isPending(Station s) => _pending?.id == s.id;

  // Se la radio si ferma o si cambia stazione, la registrazione si salva da sola
  void _onPlayer() {
    final p = RadioPlayer.i;
    final pend = _pending;
    if (pend != null) {
      if (!p.isCurrent(pend)) {
        _pending = null;
        notifyListeners();
      } else if (p.isPlaying && !p.isBuffering && !busy) {
        _pending = null;
        start();
      }
    }
    if (!recording) return;
    if (p.current?.id != station!.id || !p.wantsPlay) stopAndSave();
  }

  Future<void> start() async {
    final s = RadioPlayer.i.current;
    if (external) {
      _messages.add('C\'è già una registrazione programmata in corso');
      return;
    }
    if (s == null || busy) return;
    if (!await recNoticeAccepted()) return;
    final now = DateTime.now();
    try {
      final d = await Recordings.i.dir();
      final flag = s.flag == '🌐' ? '' : s.flag;
      final name = '$flag ${s.name} ${two(now.day)}-${two(now.month)} ${two(now.hour)}.${two(now.minute)}';
      final dst = await Recordings.i.uniquePath(name.trim(), 'm4a');
      await Recorder.streamStart(
        url: s.url,
        dir: d.path,
        name: '.rec_${now.millisecondsSinceEpoch}',
        dst: dst,
        quality: RecSettings.i.quality,
      );
    } catch (e) {
      _messages.add('Impossibile registrare questa radio');
      return;
    }
    station = s;
    startedAt = now;
    bytes = 0;
    notifyListeners();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  /// All'avvio: ricompone le registrazioni interrotte (telefono spento, batteria finita).
  Future<void> recoverInterrupted() async {
    try {
      final d = await Recordings.i.dir();
      final got = await Recorder.recover(d.path);
      if (got.isNotEmpty) {
        _messages.add(got.length == 1
            ? 'Registrazione interrotta recuperata ✔'
            : '${got.length} registrazioni interrotte recuperate ✔');
        await Recordings.i.reload();
      }
    } catch (_) {}
  }

  Future<void> _check() async {
    if (!recording) return;
    try {
      final st = await Recorder.streamStatus();
      bytes = (st['bytes'] as num?)?.toInt() ?? bytes;
      final err = st['error'] as String?;
      if (st['running'] == false) {
        if (err != null) _messages.add(err);
        await stopAndSave();
        return;
      }
      // versione gratuita: massimo 10 minuti per registrazione
      if (!Pro.i.isPro && elapsed >= Pro.freeRecLimit) {
        await stopAndSave();
        _messages.add('Registrazione salvata (10 minuti). Con Pro registri senza limiti.');
        return;
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> stopAndSave() async {
    if (!recording) return;
    _poll?.cancel();
    saving = 0; // la compressione è già fatta: resta solo l'ultimo pezzo
    notifyListeners();
    try {
      final path = await Recorder.streamStop();
      final f = path == null ? null : File(path);
      if (f == null || !f.existsSync() || f.lengthSync() < 2000) {
        _messages.add('Registrazione troppo corta, non salvata');
      } else {
        _messages.add('Salvata in Registrate · ${fmtSize(f.lengthSync())}');
      }
    } catch (_) {
      _messages.add('Registrazione non salvata');
    } finally {
      station = null;
      startedAt = null;
      saving = null;
      bytes = 0;
      notifyListeners();
      unawaited(Recordings.i.reload());
    }
  }
}

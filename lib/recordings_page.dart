import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

import 'editor.dart';
import 'paywall.dart';
import 'player.dart';
import 'pro.dart';
import 'recorder.dart';
import 'reader_page.dart';
import 'rec_player.dart';
import 'recording.dart';
import 'schedule.dart';
import 'transcript.dart' show moveTranscript, deleteTranscript;
import 'widgets.dart';
import 'i18n.dart';

class RecordingsPage extends StatefulWidget {
  const RecordingsPage({super.key});
  @override
  State<RecordingsPage> createState() => _RecordingsPageState();
}

class _RecordingsPageState extends State<RecordingsPage> {
  final _audio = AudioPlayer();
  String? _playing;
  String? _filter;
  StreamSubscription<void>? _done;

  @override
  void initState() {
    super.initState();
    Recordings.i.reload();
    Schedules.i.reload();
    _done = _audio.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _done?.cancel();
    _audio.dispose();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

  Future<void> _stopLocal() async {
    try {
      await _audio.stop();
    } catch (_) {}
    if (mounted) setState(() => _playing = null);
  }

  Future<void> _play(RecFile r) async {
    if (_playing == r.file.path) return _stopLocal();
    if (RecController.i.busy) return _snack('Ferma prima la registrazione');
    await RadioPlayer.i.stop(); // non due audio insieme
    try {
      await _audio.play(DeviceFileSource(r.file.path));
      setState(() => _playing = r.file.path);
    } catch (_) {
      _snack('Impossibile riprodurre il file');
    }
  }

  /// Rimette nell'app registrazioni salvate altrove (es. prima di reinstallare).
  Future<void> _import() async {
    FilePickerResult? res;
    try {
      res = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    } catch (_) {
      return _snack('Impossibile aprire i file');
    }
    if (res == null || res.files.isEmpty) return;
    var n = 0;
    for (final f in res.files) {
      final path = f.path;
      if (path == null) continue;
      final name = f.name;
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : 'm4a';
      try {
        final dst = await Recordings.i.uniquePath(base, ext);
        await File(path).copy(dst);
        n++;
      } catch (_) {}
    }
    await Recordings.i.reload();
    _snack(n == 1 ? '1 registrazione importata' : '$n registrazioni importate');
  }

  /// Copia di sicurezza: manda tutte le registrazioni dove vuoi (File, Drive…).
  Future<void> _exportAll() async {
    final all = Recordings.i.items;
    if (all.isEmpty) return _snack('Nessuna registrazione');
    try {
      await Share.shareXFiles([for (final r in all) XFile(r.file.path)], text: 'Registrazioni Devoo Radio');
    } catch (_) {
      _snack('Condivisione non riuscita');
    }
  }

  Future<void> _openPlayer(List<RecFile> list, int index) async {
    await _stopLocal();
    await RadioPlayer.i.stop(); // non due audio insieme
    if (!mounted) return;
    await showRecPlayer(context,
        items: List.of(list), index: index, onRead: _read, onEdit: _edit, onShare: _share);
  }

  Future<void> _read(RecFile r) async {
    if (_playing != null) await _stopLocal();
    await RadioPlayer.i.stop(); // non due audio insieme
    if (!mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ReaderPage(
                path: r.file.path,
                name: r.title.isEmpty ? r.name : r.title,
                flag: r.flag,
                duration: r.duration)));
  }

  Future<void> _rename(RecFile r) async {
    final ctrl = TextEditingController(text: r.name);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rinomina'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            helperText: tr('Per la bandiera scrivi il paese con la tastiera (es. Spain → 🇪🇸)'),
            helperMaxLines: 2,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Salva')),
        ],
      ),
    );
    ctrl.dispose();
    if (res == null) return;
    final name = cleanName(res);
    if (name.isEmpty || name == r.name) return;
    if (_playing == r.file.path) await _stopLocal();
    try {
      final dst = await Recordings.i.uniquePath(name, r.ext, except: r.file.path);
      await r.file.rename(dst);
      await moveTranscript(r.file.path, dst);
    } catch (_) {
      _snack('Rinomina non riuscita');
    }
    await Recordings.i.reload();
  }

  Future<void> _edit(RecFile r) async {
    if (!await requirePro(context, 'L\'editor per tagliare e unire è incluso in Pro.')) return;
    if (!mounted) return;
    if (RecController.i.busy) return _snack('Ferma prima la registrazione');
    await _stopLocal();
    await RadioPlayer.i.stop();
    if (!mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              EditorPage(path: r.file.path, name: r.name, quality: RecSettings.i.quality)),
    );
    if (changed == true) await Recordings.i.reload();
  }

  Future<void> _share(RecFile r) async {
    try {
      await Share.shareXFiles([XFile(r.file.path, mimeType: 'audio/mp4')], text: r.name);
    } catch (_) {
      _snack('Condivisione non riuscita');
    }
  }

  Future<void> _delete(RecFile r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare?'),
        content: Text('"${r.name}" verrà eliminata definitivamente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (ok != true) return;
    if (_playing == r.file.path) await _stopLocal();
    try {
      await r.file.delete();
      await deleteTranscript(r.file.path);
    } catch (_) {}
    await Recordings.i.reload();
  }

  void _settings() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Qualità e spazio',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
              RadioGroup<AudioQuality>(
                groupValue: RecSettings.i.quality,
                onChanged: (v) async {
                  if (v == null) return;
                  if (v != AudioQuality.voice && !Pro.i.isPro) {
                    Navigator.of(ctx).pop();
                    await openPaywall(context, reason: 'Con Pro scegli tutte le qualità audio, da 10 a 56 MB l\'ora.');
                    return;
                  }
                  RecSettings.i.setQuality(v);
                  set(() {});
                },
                child: Column(
                  children: [
                    for (final q in AudioQuality.values)
                      RadioListTile<AudioQuality>(
                        value: q,
                        title: Text(q.label),
                        subtitle: Text(q.info),
                        secondary: q != AudioQuality.voice && !Pro.i.isPro
                            ? const Icon(Icons.lock_outline, size: 20)
                            : null,
                      ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                    'Formato M4A (AAC): si apre su WhatsApp, email, Android e iPhone. '
                    'La radio viene registrata direttamente dallo stream, senza perdite e senza rumori.',
                    style: TextStyle(fontSize: 12)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Text('Sviluppata da ${Pro.developer} · ${Pro.website}',
                    style: const TextStyle(fontSize: 12, color: Colors.white54)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([Recordings.i, RecController.i]),
        builder: (context, _) {
          final all = Recordings.i.items;
          final flags = all.map((r) => r.flag).whereType<String>().toSet().toList();
          final f = _filter != null && flags.contains(_filter) ? _filter : null;
          final shown = f == null ? all : all.where((r) => r.flag == f).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('Registrate',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
                    ),
                    if (!Pro.i.isPro)
                      TextButton.icon(
                        icon: const Icon(Icons.workspace_premium, color: accent),
                        label: const Text('Pro'),
                        onPressed: () => openPaywall(context),
                      ),
                    IconButton(
                      tooltip: 'Programma registrazione',
                      icon: const Icon(Icons.alarm_add, color: recRed),
                      onPressed: () => openScheduleEditor(context),
                    ),
                    IconButton(
                      tooltip: 'Qualità',
                      icon: const Icon(Icons.tune),
                      onPressed: _settings,
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'import') _import();
                        if (v == 'export') _exportAll();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'import',
                            child: ListTile(
                                leading: Icon(Icons.file_download_outlined),
                                title: Text('Importa registrazioni'))),
                        PopupMenuItem(
                            value: 'export',
                            child: ListTile(
                                leading: Icon(Icons.ios_share), title: Text('Salva una copia di tutte'))),
                      ],
                    ),
                  ],
                ),
              ),
              const ScheduleList(),
              if (flags.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('Tutte'),
                          selected: f == null,
                          onSelected: (_) => setState(() => _filter = null),
                        ),
                      ),
                      for (final fl in flags)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(fl, style: const TextStyle(fontSize: 20)),
                            selected: f == fl,
                            onSelected: (_) => setState(() => _filter = fl),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: shown.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'Nessuna registrazione.\nAscolta una radio e premi ● Registra.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) => _tile(shown[i], scheme, shown, i),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(RecFile r, ColorScheme scheme, List<RecFile> list, int index) {
    final playing = _playing == r.file.path;
    final d = r.duration;
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: scheme.surfaceContainerHighest,
        child: Text(r.flag ?? '🎙', style: const TextStyle(fontSize: 22)),
      ),
      title: Text(r.title.isEmpty ? r.name : r.title,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
          '${fmtDate(r.date)} · ${d == null ? '…' : fmtDur(d)} · ${fmtSize(r.size)}'),
      onTap: () => _openPlayer(list, index),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 32,
            icon: Icon(playing ? Icons.stop_circle : Icons.play_circle_outline,
                color: playing ? accent : null),
            onPressed: () => playing ? _play(r) : _openPlayer(list, index),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'read') _read(r);
              if (v == 'edit') _edit(r);
              if (v == 'rename') _rename(r);
              if (v == 'share') _share(r);
              if (v == 'delete') _delete(r);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'read',
                  child: ListTile(
                      leading: Icon(Icons.menu_book_rounded, color: accent),
                      title: Text('Leggi e traduci'))),
              PopupMenuItem(
                  value: 'edit',
                  child: ListTile(leading: Icon(Icons.content_cut), title: Text('Modifica / taglia'))),
              PopupMenuItem(
                  value: 'rename',
                  child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Rinomina'))),
              PopupMenuItem(
                  value: 'share',
                  child: ListTile(
                      leading: Icon(Icons.share), title: Text('Condividi (WhatsApp, email…)'))),
              PopupMenuItem(
                  value: 'delete',
                  child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Elimina'))),
            ],
          ),
        ],
      ),
    );
  }
}

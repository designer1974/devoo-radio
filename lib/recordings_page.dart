import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'editor.dart';
import 'player.dart';
import 'recorder.dart';
import 'recording.dart';
import 'schedule.dart';
import 'widgets.dart';

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
          decoration: const InputDecoration(
            helperText: 'Per la bandiera scrivi il paese con la tastiera (es. Spain → 🇪🇸)',
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
    } catch (_) {
      _snack('Rinomina non riuscita');
    }
    await Recordings.i.reload();
  }

  Future<void> _edit(RecFile r) async {
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
                onChanged: (v) {
                  if (v == null) return;
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
                        itemBuilder: (_, i) => _tile(shown[i], scheme),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(RecFile r, ColorScheme scheme) {
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
      onTap: () => _play(r),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            iconSize: 32,
            icon: Icon(playing ? Icons.stop_circle : Icons.play_circle_outline,
                color: playing ? accent : null),
            onPressed: () => _play(r),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _edit(r);
              if (v == 'rename') _rename(r);
              if (v == 'share') _share(r);
              if (v == 'delete') _delete(r);
            },
            itemBuilder: (_) => const [
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

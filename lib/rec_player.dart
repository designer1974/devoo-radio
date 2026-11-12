// Player di una registrazione: si apre toccando il file.
// Barra del tempo, ±10 s, precedente / successiva, velocità,
// e riprende da dove eri rimasto (utile per le registrazioni di ore).

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart' show tr;
import 'recording.dart';
import 'widgets.dart' show accent;

Future<void> showRecPlayer(
  BuildContext context, {
  required List<RecFile> items,
  required int index,
  required void Function(RecFile) onRead,
  required void Function(RecFile) onEdit,
  required void Function(RecFile) onShare,
}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _RecPlayer(items: items, index: index, onRead: onRead, onEdit: onEdit, onShare: onShare),
    );

class _RecPlayer extends StatefulWidget {
  final List<RecFile> items;
  final int index;
  final void Function(RecFile) onRead, onEdit, onShare;
  const _RecPlayer(
      {required this.items, required this.index, required this.onRead, required this.onEdit, required this.onShare});

  @override
  State<_RecPlayer> createState() => _RecPlayerState();
}

class _RecPlayerState extends State<_RecPlayer> {
  final _p = AudioPlayer();
  late int _i = widget.index;
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _playing = false;
  bool _dragging = false;
  double _speed = 1.0;
  final _subs = <StreamSubscription>[];
  DateTime _lastSave = DateTime(0);

  RecFile get _r => widget.items[_i];

  @override
  void initState() {
    super.initState();
    _subs.addAll([
      _p.onPositionChanged.listen((d) {
        if (!_dragging && mounted) setState(() => _pos = d);
        if (DateTime.now().difference(_lastSave).inSeconds >= 5) {
          _lastSave = DateTime.now();
          _savePos();
        }
      }),
      _p.onDurationChanged.listen((d) {
        if (mounted) setState(() => _dur = d);
      }),
      _p.onPlayerStateChanged.listen((s) {
        if (mounted) setState(() => _playing = s == PlayerState.playing);
      }),
      _p.onPlayerComplete.listen((_) {
        _pos = Duration.zero;
        _savePos(reset: true);
        if (mounted) setState(() => _playing = false);
      }),
    ]);
    _open();
  }

  String get _key => 'pos|${_r.file.path.split('/').last}';

  Future<void> _savePos({bool reset = false}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final ms = _pos.inMilliseconds;
      if (reset || ms < 5000 || (_dur.inMilliseconds > 0 && _dur.inMilliseconds - ms < 5000)) {
        await p.remove(_key);
      } else {
        await p.setInt(_key, ms);
      }
    } catch (_) {}
  }

  Future<void> _open() async {
    setState(() {
      _pos = Duration.zero;
      _dur = _r.duration ?? Duration.zero;
    });
    try {
      await _p.stop();
      await _p.setSource(DeviceFileSource(_r.file.path));
      var start = 0;
      try {
        start = (await SharedPreferences.getInstance()).getInt(_key) ?? 0;
      } catch (_) {}
      if (start > 0) {
        await _p.seek(Duration(milliseconds: start));
        if (mounted) setState(() => _pos = Duration(milliseconds: start));
      }
      await _p.setPlaybackRate(_speed);
      await _p.resume();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Impossibile riprodurre il file'))));
      }
    }
  }

  @override
  void dispose() {
    _savePos();
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    super.dispose();
  }

  Future<void> _go(int i) async {
    if (i < 0 || i >= widget.items.length) return;
    await _savePos();
    setState(() => _i = i);
    await _open();
  }

  Future<void> _skip(int sec) async {
    final max = _dur.inMilliseconds;
    var ms = _pos.inMilliseconds + sec * 1000;
    if (ms < 0) ms = 0;
    if (max > 0 && ms > max - 500) ms = max - 500;
    await _p.seek(Duration(milliseconds: ms));
    setState(() => _pos = Duration(milliseconds: ms));
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _p.pause();
      _savePos();
    } else {
      await _p.setPlaybackRate(_speed);
      await _p.resume();
    }
  }

  Future<void> _nextSpeed() async {
    const speeds = [1.0, 1.25, 1.5, 2.0, 0.75];
    final i = speeds.indexOf(_speed);
    setState(() => _speed = speeds[(i + 1) % speeds.length]);
    if (_playing) await _p.setPlaybackRate(_speed);
  }

  void _action(void Function(RecFile) f) {
    final r = _r;
    _savePos();
    _p.stop();
    Navigator.pop(context);
    f(r);
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final r = _r;
    final maxMs = _dur.inMilliseconds <= 0 ? 1.0 : _dur.inMilliseconds.toDouble();
    final posMs = _pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
    final speedLabel = _speed == _speed.roundToDouble() ? '${_speed.toInt()}×' : '$_speed×';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: s.surfaceContainerHighest,
            child: Text(r.flag ?? '🎙', style: const TextStyle(fontSize: 40)),
          ),
          const SizedBox(height: 12),
          Text(r.title.isEmpty ? r.name : r.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${fmtDate(r.date)} · ${fmtSize(r.size)} · ${_i + 1}/${widget.items.length}',
              style: TextStyle(color: s.onSurfaceVariant)),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 4, activeTrackColor: accent, thumbColor: accent),
            child: Slider(
              value: posMs,
              max: maxMs,
              onChangeStart: (_) => _dragging = true,
              onChanged: (v) => setState(() => _pos = Duration(milliseconds: v.round())),
              onChangeEnd: (v) async {
                await _p.seek(Duration(milliseconds: v.round()));
                _dragging = false;
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Text(fmtDur(_pos), style: TextStyle(color: s.onSurfaceVariant)),
                const Spacer(),
                Text(fmtDur(_dur), style: TextStyle(color: s.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 34,
                tooltip: tr('Precedente'),
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: _i > 0 ? () => _go(_i - 1) : null,
              ),
              IconButton(iconSize: 32, icon: const Icon(Icons.replay_10_rounded), onPressed: () => _skip(-10)),
              IconButton.filled(
                iconSize: 46,
                style: IconButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: _toggle,
              ),
              IconButton(iconSize: 32, icon: const Icon(Icons.forward_10_rounded), onPressed: () => _skip(10)),
              IconButton(
                iconSize: 34,
                tooltip: tr('Successiva'),
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: _i < widget.items.length - 1 ? () => _go(_i + 1) : null,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ActionChip(label: Text('⏩ $speedLabel'), onPressed: _nextSpeed),
              const SizedBox(width: 8),
              ActionChip(label: const Text('−1 min'), onPressed: () => _skip(-60)),
              const SizedBox(width: 8),
              ActionChip(label: const Text('+1 min'), onPressed: () => _skip(60)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _action(widget.onRead),
                  icon: const Icon(Icons.menu_book_rounded),
                  label: Text(tr('Leggi e traduci'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: tr('Modifica / taglia'),
                  onPressed: () => _action(widget.onEdit),
                  icon: const Icon(Icons.content_cut)),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  tooltip: tr('Condividi'),
                  onPressed: () => _action(widget.onShare),
                  icon: const Icon(Icons.share)),
            ],
          ),
        ],
      ),
    );
  }
}

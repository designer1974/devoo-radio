import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'models.dart';
import 'recorder.dart';
import 'recording.dart';
import 'widgets.dart';

/// Una registrazione programmata.
class Schedule {
  final String id;
  final String name;
  final String flag;
  final String url;
  final DateTime start;
  final DateTime end;
  final bool daily;
  final bool running;

  const Schedule(this.id, this.name, this.flag, this.url, this.start, this.end, this.daily, this.running);

  Duration get length => end.difference(start);

  static Schedule? from(Map m) {
    try {
      return Schedule(
        '${m['id']}',
        '${m['name'] ?? ''}',
        '${m['flag'] ?? ''}',
        '${m['url'] ?? ''}',
        DateTime.fromMillisecondsSinceEpoch((m['start'] as num).toInt()),
        DateTime.fromMillisecondsSinceEpoch((m['end'] as num).toInt()),
        m['daily'] == true,
        m['running'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

String fmtLen(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? (h == 1 ? '1 ora' : '$h ore') : '$h h $m min';
}

String hhmm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'oggi';
  if (diff == 1) return 'domani';
  return '${two(d.day)}/${two(d.month)}';
}

class Schedules extends ChangeNotifier {
  Schedules._();
  static final i = Schedules._();
  static const _ch = MethodChannel('rr/recorder');

  List<Schedule> items = [];

  Future<void> reload() async {
    try {
      final l = await _ch.invokeMethod<List>('schedList') ?? const [];
      items = l.whereType<Map>().map(Schedule.from).whereType<Schedule>().toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> add(Station s, DateTime start, DateTime end, bool daily) async {
    final dir = await Recordings.i.dir();
    final q = RecSettings.i.quality;
    await _ch.invokeMethod('schedAdd', {
      'id': '${DateTime.now().microsecondsSinceEpoch}',
      'name': s.name,
      'flag': s.flag == '🌐' ? '' : s.flag,
      'url': s.url,
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'daily': daily,
      'dir': dir.path,
      'bitrate': q.bitrate,
      'outCh': q.outCh,
      'he': q.he,
    });
    await reload();
  }

  Future<void> remove(Schedule s) async {
    try {
      await _ch.invokeMethod('schedRemove', {'id': s.id});
    } catch (_) {}
    await reload();
  }

  Future<bool> exactOk() async {
    try {
      return await _ch.invokeMethod<bool>('schedExactOk') ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> openExactSettings() async {
    try {
      await _ch.invokeMethod('schedExactSettings');
    } catch (_) {}
  }
}

void openScheduleEditor(BuildContext context, {Station? station}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScheduleEditor(station: station)));
}

/// Programma: radio, inizio, fine, ogni giorno.
class ScheduleEditor extends StatefulWidget {
  const ScheduleEditor({super.key, this.station});
  final Station? station;
  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  Station? _station;
  late DateTime _start;
  late TimeOfDay _endTime;
  bool _daily = false;
  bool _saving = false;

  final _q = TextEditingController();
  List<Station>? _results;
  bool _searching = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _station = widget.station;
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day, now.hour + 1);
    final e = _start.add(const Duration(hours: 1));
    _endTime = TimeOfDay(hour: e.hour, minute: e.minute);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  /// La fine è sempre dopo l'inizio: se l'ora è minore, è il giorno dopo (es. 23:00 → 03:00).
  DateTime get _end {
    var e = DateTime(_start.year, _start.month, _start.day, _endTime.hour, _endTime.minute);
    if (!e.isAfter(_start)) e = e.add(const Duration(days: 1));
    return e;
  }

  Future<void> _search(String text) async {
    final q = text.trim();
    final seq = ++_seq;
    if (q.length < 2) {
      setState(() => _results = null);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await RadioApi.i.searchAll(q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = r;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
    }
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(now) ? now : _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
  }

  Future<void> _pickStart() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _start.hour, minute: _start.minute),
      helpText: 'Inizio registrazione',
    );
    if (t == null) return;
    setState(() {
      _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
      // orario già passato oggi → domani
      if (_start.isBefore(DateTime.now().subtract(const Duration(minutes: 1)))) {
        _start = _start.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _pickEnd() async {
    final t = await showTimePicker(context: context, initialTime: _endTime, helpText: 'Fine registrazione');
    if (t != null) setState(() => _endTime = t);
  }

  Future<void> _save() async {
    final s = _station;
    if (s == null || _saving) return;
    if (_end.difference(_start).inMinutes < 1) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      if (!await Schedules.i.exactOk() && mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Permesso per l\'orario esatto'),
            content: const Text(
                'Per partire esattamente all\'ora scelta, Android chiede di attivare «Sveglie e promemoria» per Devoo Radio Pro.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Dopo')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Attiva')),
            ],
          ),
        );
        if (go == true) await Schedules.i.openExactSettings();
      }
      await Schedules.i.add(s, _start, _end, _daily);
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Programmata: ${s.name}, ${dayLabel(_start)} ${hhmm(_start)} → ${hhmm(_end)}'),
      ));
      nav.pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(const SnackBar(content: Text('Non riuscito, riprova')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _station;
    final len = _end.difference(_start);
    return Scaffold(
      appBar: AppBar(title: const Text('Programma registrazione')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Radio', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          if (s != null)
            ListTile(
              leading: StationLogo(s),
              title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${s.flag} ${s.place}'),
              trailing: TextButton(
                onPressed: () => setState(() => _station = null),
                child: const Text('Cambia'),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _q,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Scrivi il nome, es. Fox News',
                  border: OutlineInputBorder(),
                ),
                onChanged: _search,
              ),
            ),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            for (final r in (_results ?? const <Station>[]).take(30))
              ListTile(
                leading: StationLogo(r, size: 40),
                title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${r.flag} ${r.place}', maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => setState(() {
                  _station = r;
                  _results = null;
                  _q.clear();
                }),
              ),
            if (_results != null && _results!.isEmpty && !_searching)
              const Padding(padding: EdgeInsets.all(16), child: Text('Nessuna radio trovata')),
          ],
          const Divider(height: 28),
          ListTile(
            leading: const Icon(Icons.calendar_today),
            title: const Text('Giorno'),
            trailing: Text(dayLabel(_start), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            onTap: _pickDay,
          ),
          ListTile(
            leading: const Icon(Icons.play_circle_outline, color: recRed),
            title: const Text('Inizio'),
            trailing: Text(hhmm(_start), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            onTap: _pickStart,
          ),
          ListTile(
            leading: const Icon(Icons.stop_circle_outlined),
            title: const Text('Fine'),
            subtitle: _end.day != _start.day ? const Text('il giorno dopo') : null,
            trailing: Text(hhmm(_end), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            onTap: _pickEnd,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text('Durata: ${fmtLen(len)} · circa ${(len.inMinutes / 60 * _mbPerHour()).toStringAsFixed(0)} MB',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.repeat),
            title: const Text('Ogni giorno'),
            subtitle: const Text('Registra alla stessa ora tutti i giorni'),
            value: _daily,
            onChanged: (v) => setState(() => _daily = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: recRed, padding: const EdgeInsets.symmetric(vertical: 16)),
              icon: const Icon(Icons.alarm_add),
              label: Text(_saving ? 'Salvo…' : 'Programma'),
              onPressed: s == null || _saving ? null : _save,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Funziona anche con l\'app chiusa e lo schermo spento: serve solo internet. '
              'Su Huawei: Impostazioni → Batteria → Avvio app → Devoo Radio Pro → gestisci manualmente e attiva tutto, '
              'così il telefono non la blocca di notte.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  double _mbPerHour() => RecSettings.i.quality.bitrate / 8 * 3600 / 1000000;
}

/// Elenco delle registrazioni programmate (nella pagina Registrate).
class ScheduleList extends StatelessWidget {
  const ScheduleList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Schedules.i,
      builder: (context, _) {
        final items = Schedules.i.items;
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final s in items)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: Icon(s.running ? Icons.fiber_manual_record : Icons.alarm,
                      color: s.running ? recRed : accent),
                  title: Text('${s.flag} ${s.name}'.trim(),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(s.running
                      ? 'Sta registrando · fino alle ${hhmm(s.end)}'
                      : '${s.daily ? 'Ogni giorno' : dayLabel(s.start)} ${hhmm(s.start)} → ${hhmm(s.end)} · ${fmtLen(s.length)}'),
                  trailing: IconButton(
                    tooltip: s.running ? 'Ferma' : 'Elimina',
                    icon: const Icon(Icons.close),
                    onPressed: () => Schedules.i.remove(s),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

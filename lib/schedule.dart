import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import 'api.dart';
import 'models.dart';
import 'paywall.dart';
import 'recorder.dart';
import 'recording.dart';
import 'widgets.dart';
import 'i18n.dart';

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

  Future<void> stopRunning() async {
    try {
      await _ch.invokeMethod('schedStop');
    } catch (_) {}
  }

  /// Programmi che si sovrappongono a questo orario.
  List<Schedule> overlapping(DateTime start, DateTime end) =>
      items.where((x) => x.start.isBefore(end) && start.isBefore(x.end)).toList();

  Future<bool> exactOk() async {
    try {
      return await _ch.invokeMethod<bool>('schedExactOk') ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> batteryOk() async {
    try {
      return await _ch.invokeMethod<bool>('batteryOk') ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> batteryAsk() async {
    try {
      await _ch.invokeMethod('batteryAsk');
    } catch (_) {}
  }

  Future<bool> isHuawei() async {
    try {
      return await _ch.invokeMethod<bool>('isHuawei') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> openAutostart() async {
    try {
      await _ch.invokeMethod('openAutostart');
    } catch (_) {}
  }

  Future<void> openExactSettings() async {
    try {
      await _ch.invokeMethod('schedExactSettings');
    } catch (_) {}
  }
}

Future<void> openScheduleEditor(BuildContext context, {Station? station}) async {
  if (!await requirePro(context, 'Le registrazioni programmate sono incluse in Pro. Provalo gratis per 7 giorni.')) return;
  if (!context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScheduleEditor(station: station)));
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
  int _day = 0; // 0 = oggi, 1 = domani…
  int? _startMin; // minuti dalla mezzanotte; null = adesso
  int _durMin = 60;
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
    // proposta: il prossimo quarto d'ora
    final now = DateTime.now();
    final m = now.hour * 60 + now.minute;
    final next = ((m ~/ 15) + 1) * 15;
    if (next >= 24 * 60) {
      _day = 1;
      _startMin = next - 24 * 60;
    } else {
      _startMin = next;
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  DateTime _dayBase(int d) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).add(Duration(days: d));
  }

  DateTime get _start {
    final m = _startMin;
    if (m == null) return DateTime.now();
    final b = _dayBase(_day);
    return DateTime(b.year, b.month, b.day, m ~/ 60, m % 60);
  }

  DateTime get _end => _start.add(Duration(minutes: _durMin));

  String _hm(int m) => '${two(m ~/ 60)}:${two(m % 60)}';

  String _dayName(int d) {
    if (d == 0) return 'Oggi';
    if (d == 1) return 'Domani';
    final b = _dayBase(d);
    final w = weekdayName(b.weekday);
    return '${w[0].toUpperCase()}${w.substring(1)} ${b.day}';
  }

  /// Orari possibili di inizio (ogni 15 minuti); oggi solo quelli futuri, più «Adesso».
  List<int?> _startOptions() {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final list = <int?>[];
    if (_day == 0) list.add(null);
    for (var m = 0; m < 24 * 60; m += 15) {
      if (_day == 0 && m <= nowMin) continue;
      list.add(m);
    }
    return list;
  }

  void _setDay(int d) {
    setState(() {
      _day = d;
      final opts = _startOptions();
      if (!opts.contains(_startMin)) _startMin = opts.firstWhere((x) => x != null, orElse: () => null);
      if (_day != 0 && _startMin == null) _startMin = 0;
    });
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

  Future<void> _save() async {
    final s = _station;
    if (s == null || _saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      if (!await Schedules.i.exactOk() && mounted) await Schedules.i.openExactSettings();
      if (!await Schedules.i.batteryOk()) await Schedules.i.batteryAsk();
      final st = _start;
      final en = _end;
      await Schedules.i.reload();
      final clash = Schedules.i.overlapping(st, en);
      if (clash.isNotEmpty && mounted) {
        final c = clash.first;
        final replace = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Orario già occupato'),
            content: Text('C\'è già «${c.name}» dalle ${hhmm(c.start)} alle ${hhmm(c.end)}.\nSi registra una radio alla volta.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sostituisci')),
            ],
          ),
        );
        if (replace != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        for (final x in clash) {
          await Schedules.i.remove(x);
        }
        if (clash.any((x) => x.running)) await Future<void>.delayed(const Duration(seconds: 3));
      }
      await Schedules.i.add(s, _startMin == null ? DateTime.now() : st, en, _daily);
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(_startMin == null
            ? 'Registrazione iniziata: ${s.name}, fino alle ${hhmm(en)}'
            : 'Programmata: ${s.name}, ${dayLabel(st)} ${hhmm(st)} → ${hhmm(en)}'),
      ));
      nav.pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(const SnackBar(content: Text('Non riuscito, riprova')));
      }
    }
  }

  Widget _box<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) text,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      key: ValueKey('$label|$value|${items.length}'), // si aggiorna quando cambia il valore
      initialValue: value,
      isExpanded: true,
      menuMaxHeight: 360,
      borderRadius: BorderRadius.circular(12),
      decoration: InputDecoration(
        labelText: tr(label),
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.fromLTRB(12, 14, 6, 14),
      ),
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
      items: [for (final it in items) DropdownMenuItem<T>(value: it, child: Text(text(it), overflow: TextOverflow.ellipsis))],
      onChanged: (v) {
        if (v != null || null is T) onChanged(v as T);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _station;
    final startOpts = _startOptions();
    if (!startOpts.contains(_startMin)) _startMin = startOpts.isEmpty ? null : startOpts.first;
    final st = _start;
    const durs = [15, 30, 45, 60, 90, 120, 150, 180, 240, 300, 360, 480, 600, 720];
    final mb = _durMin / 60 * RecSettings.i.quality.bitrate / 8 * 3600 / 1000000;
    final en = _end;
    final nextDay = en.day != st.day;

    return Scaffold(
      appBar: AppBar(title: const Text('Programma registrazione')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: [
          if (s != null)
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: StationLogo(s, size: 44),
                title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${s.flag} ${s.place}', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: TextButton(onPressed: () => setState(() => _station = null), child: const Text('Cambia')),
              ),
            )
          else ...[
            TextField(
              controller: _q,
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Scrivi la radio, es. Fox News'),
                border: const OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
            if (_searching) const LinearProgressIndicator(minHeight: 2),
            for (final r in (_results ?? const <Station>[]).take(30))
              ListTile(
                contentPadding: EdgeInsets.zero,
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
          const SizedBox(height: 18),
          _box<int>(
            label: 'Giorno',
            value: _day,
            items: List.generate(7, (i) => i),
            text: _dayName,
            onChanged: _setDay,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _box<int?>(
                  label: 'Inizio',
                  value: _startMin,
                  items: startOpts,
                  text: (m) => m == null ? 'Adesso' : _hm(m),
                  onChanged: (m) => setState(() => _startMin = m),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _box<int>(
                  label: 'Fine',
                  value: _durMin,
                  items: durs,
                  text: (d) {
                    final e = st.add(Duration(minutes: d));
                    final h = d ~/ 60, m = d % 60;
                    final len = h == 0 ? '$m min' : (m == 0 ? '$h h' : '$h h $m');
                    return '${hhmm(e)}  ($len)';
                  },
                  onChanged: (d) => setState(() => _durMin = d),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Ogni giorno', style: TextStyle(fontSize: 16)),
            value: _daily,
            onChanged: (v) => setState(() => _daily = v),
          ),
          Text(
            '${_startMin == null ? 'Da adesso' : '${_dayName(_day)} dalle ${hhmm(st)}'} alle ${hhmm(en)}'
            '${nextDay ? ' del giorno dopo' : ''} · circa ${mb.toStringAsFixed(0)} MB',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
      // pulsante sempre visibile, senza scorrere
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: recRed,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: recRed.withValues(alpha: 0.35),
                    disabledForegroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: Icon(_startMin == null ? Icons.fiber_manual_record : Icons.alarm_add),
                  label: Text(
                    s == null
                        ? 'Scegli prima la radio'
                        : _saving
                            ? 'Salvo…'
                            : (_startMin == null ? 'Inizia a registrare' : 'Programma alle ${hhmm(st)}'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  onPressed: s == null || _saving ? null : _save,
                ),
              ),
            ),
            const PlayerBar(),
          ],
        ),
      ),
    );
  }
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

import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import 'api.dart';
import 'cities.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'i18n.dart';

const _genres = [
  ('Pop', 'pop'),
  ('Rock', 'rock'),
  ('News', 'news'),
  ('Jazz', 'jazz'),
  ('Classica', 'classical'),
  ('Dance', 'dance'),
  ('Hip hop', 'hip hop'),
  ('Arabo', 'arabic'),
  ('Corano', 'quran'),
  ('Chaabi', 'chaabi'),
  ('Raï', 'rai'),
  ('Italiano', 'italian'),
  ('Latino', 'latin'),
  ('Reggae', 'reggae'),
  ('Chill', 'chillout'),
  ('Sport', 'sport'),
  ('Anni 80', '80s'),
  ('Talk', 'talk'),
];

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(() {
      if (!_tabs.indexIsChanging) _run();
    });
  final _text = TextEditingController();
  Timer? _debounce;
  int _seq = 0;
  bool _loading = false;
  String? _error;
  List<Station>? _results;

  List<Country>? _countries;
  bool _countriesFailed = false;

  @override
  void initState() {
    super.initState();
    _loadCountries();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    setState(() => _countriesFailed = false);
    try {
      final c = await RadioApi.i.countries();
      if (mounted) setState(() => _countries = c);
    } catch (_) {
      if (mounted) setState(() => _countriesFailed = true);
    }
  }

  void _changed(String _) {
    setState(() {}); // aggiorna la X e il filtro paesi
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550), _run);
  }

  Future<void> _run() async {
    final q = _text.text.trim();
    final tab = _tabs.index;
    final seq = ++_seq;
    if (tab == 1 || q.length < 2) {
      setState(() {
        _results = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = tab == 2
          ? await RadioApi.i.search(tag: q.toLowerCase())
          : await RadioApi.i.searchAll(q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = 'Ricerca non riuscita. Controlla la connessione.';
      });
    }
  }

  void _genre(String tag) {
    _text.text = tag;
    _run();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: SearchBar(
              controller: _text,
              hintText: tr(switch (_tabs.index) {
                1 => 'Paese: Marocco, Italia, Egypt…',
                2 => 'Genere: jazz, news, quran…',
                _ => 'Nome della radio o città',
              }),
              leading: const Icon(Icons.search),
              trailing: [
                if (_text.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _text.clear();
                      _changed('');
                    },
                  ),
              ],
              onChanged: _changed,
              onSubmitted: (_) => _run(),
            ),
          ),
          TabBar(
            controller: _tabs,
            onTap: (_) => setState(() {}),
            tabs: [
              Tab(icon: const Icon(Icons.radio), text: tr('Radio')),
              Tab(icon: const Icon(Icons.flag), text: tr('Paesi')),
              Tab(icon: const Icon(Icons.music_note), text: tr('Generi')),
            ],
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _stationsOr(_topStations()),
                _countryList(),
                _stationsOr(_genreChips()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stationsOr(Widget empty) {
    final r = _results;
    if (_error != null) return Center(child: Text(_error!));
    if (r == null) return empty;
    if (r.isEmpty) {
      return const Center(
          child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Nessuna radio trovata.\nProva un nome più corto (es. «Medi» invece di «Medi1»).',
            textAlign: TextAlign.center),
      ));
    }
    return ListView.builder(itemCount: r.length, itemBuilder: (_, i) => StationTile(r[i]));
  }

  Widget _topStations() {
    final top = StationStore.i.stations.take(40).toList();
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('Le più ascoltate nel mondo',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        for (final s in top) StationTile(s),
      ],
    );
  }

  Widget _genreChips() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, tag) in _genres)
              ActionChip(label: Text(label), onPressed: () => _genre(tag)),
          ],
        ),
      ],
    );
  }

  Widget _countryList() {
    final all = _countries;
    if (all == null) {
      return Center(
        child: _countriesFailed
            ? TextButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Paesi non caricati, riprova'),
                onPressed: _loadCountries)
            : const CircularProgressIndicator(),
      );
    }
    final list = all.where((c) => c.matches(_text.text)).toList();
    if (list.isEmpty) return const Center(child: Text('Nessun paese trovato'));
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final c = list[i];
        return ListTile(
          leading: Text(c.flag, style: const TextStyle(fontSize: 30)),
          title: Text(c.displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${c.count} radio'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => CountryPage(country: c))),
        );
      },
    );
  }
}

/// Un paese: prima l'elenco delle città (con quante radio), poi le radio di ogni città.
class CountryPage extends StatefulWidget {
  const CountryPage({super.key, required this.country});
  final Country country;
  @override
  State<CountryPage> createState() => _CountryPageState();
}

class _City {
  _City(this.name);
  final String name;
  final List<Station> stations = [];
}

const _otherCity = 'Radio nazionali e web';

class _CountryPageState extends State<CountryPage> {
  List<Station>? _list;
  List<_City> _cities = const [];
  bool _failed = false;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final r = await RadioApi.i.search(countryCode: widget.country.code, limit: 5000);
      final cities = await _group(r);
      if (!mounted) return;
      setState(() {
        _list = r;
        _cities = cities;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Ogni radio nella sua città vera; le altre sono nazionali o solo web.
  Future<List<_City>> _group(List<Station> all) async {
    CityIndex? idx;
    try {
      idx = await CityIndex.of(widget.country.code);
    } catch (_) {}
    final map = <String, _City>{};
    final pop = <String, int>{};
    final assigned = idx?.assignAll(all, widget.country.code) ?? const {};
    for (final st in all) {
      final city = assigned[st.id];
      final name = city?.name ?? _otherCity;
      map.putIfAbsent(name, () => _City(name)).stations.add(st);
      if (city != null) pop[name] = city.population;
    }
    final out = map.values.toList()
      ..sort((a, b) {
        if (a.name == _otherCity) return 1;
        if (b.name == _otherCity) return -1;
        final c = b.stations.length.compareTo(a.stations.length);
        return c != 0 ? c : (pop[b.name] ?? 0).compareTo(pop[a.name] ?? 0);
      });
    return out;
  }

  void _openCity(_City c) {
    final country = widget.country;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _CityPage(
        title: c.name == _otherCity ? tr(_otherCity) : c.name,
        subtitle: '${country.flag}  ${country.displayName}',
        stations: c.stations,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.country;
    final all = _list;
    final f = _filter.toLowerCase();
    final cities = f.isEmpty
        ? _cities
        : _cities.where((x) => x.name.toLowerCase().contains(f)).toList();
    // radio che corrispondono al filtro (nome o genere), in qualsiasi città
    final stations = f.isEmpty
        ? const <Station>[]
        : (all ?? const <Station>[])
            .where((s) => s.name.toLowerCase().contains(f) || s.tags.toLowerCase().contains(f))
            .take(200)
            .toList();
    final realCities = _cities.where((x) => x.name != _otherCity).length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${c.flag}  ${c.displayName}'),
            if (all != null)
              Text(tr('{} radio · {} città').replaceFirst('{}', '${all.length}').replaceFirst('{}', '$realCities'),
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      bottomNavigationBar: const PlayerBar(),
      body: all == null
          ? Center(
              child: _failed
                  ? TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Non caricato, riprova'),
                      onPressed: _load)
                  : const CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr('Cerca città o radio'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _filter = v.trim()),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (f.isEmpty)
                        _CityTile(
                          name: tr('Tutte le radio'),
                          count: all.length,
                          icon: Icons.public,
                          onTap: () => _openCity(_City(tr('Tutte le radio'))..stations.addAll(all)),
                        ),
                      for (final x in cities)
                        _CityTile(
                          name: x.name == _otherCity ? tr(_otherCity) : x.name,
                          count: x.stations.length,
                          icon: x.name == _otherCity ? Icons.more_horiz : null,
                          onTap: () => _openCity(x),
                        ),
                      if (stations.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(tr('Radio'), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        for (final s in stations) StationTile(s),
                      ],
                      if (cities.isEmpty && stations.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('Nessun risultato')),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Una città con il numero delle radio in un cerchio verde.
class _CityTile extends StatelessWidget {
  const _CityTile({required this.name, required this.count, required this.onTap, this.icon});
  final String name;
  final int count;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            radius: 22,
            backgroundColor: accent,
            foregroundColor: Colors.black,
            child: icon != null
                ? Icon(icon, color: Colors.black)
                : Text('$count', style: TextStyle(fontWeight: FontWeight.w700, fontSize: count > 999 ? 12 : 15)),
          ),
          title: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          subtitle: Text(count == 1 ? '1 radio' : tr('{} radio').replaceFirst('{}', '$count')),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
        const Divider(height: 1, indent: 72),
      ],
    );
  }
}

/// Le radio di una città.
class _CityPage extends StatelessWidget {
  const _CityPage({required this.title, required this.subtitle, required this.stations});
  final String title;
  final String subtitle;
  final List<Station> stations;

  @override
  Widget build(BuildContext context) {
    final n = stations.length;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Text('$subtitle · ${n == 1 ? '1 radio' : tr('{} radio').replaceFirst('{}', '$n')}',
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
      bottomNavigationBar: const PlayerBar(),
      body: ListView.builder(
        itemCount: n,
        itemBuilder: (_, i) => StationTile(stations[i]),
      ),
    );
  }
}

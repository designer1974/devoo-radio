import 'dart:async';

import 'package:flutter/material.dart' hide Text;

import 'api.dart';
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

/// Tutte le radio di un paese.
class CountryPage extends StatefulWidget {
  const CountryPage({super.key, required this.country});
  final Country country;
  @override
  State<CountryPage> createState() => _CountryPageState();
}

class _CountryPageState extends State<CountryPage> {
  List<Station>? _list;
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
      final r = await RadioApi.i.search(countryCode: widget.country.code, limit: 1000);
      if (mounted) setState(() => _list = r);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.country;
    final all = _list;
    final f = _filter.toLowerCase();
    final list = all
        ?.where((s) =>
            f.isEmpty ||
            s.name.toLowerCase().contains(f) ||
            s.state.toLowerCase().contains(f) ||
            s.tags.toLowerCase().contains(f))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text('${c.flag}  ${c.displayName}')),
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
                      prefixIcon: const Icon(Icons.filter_list),
                      hintText: tr('Filtra ${all.length} radio (nome, città, genere)'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _filter = v.trim()),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: list!.length,
                    itemBuilder: (_, i) => StationTile(list[i]),
                  ),
                ),
              ],
            ),
    );
  }
}

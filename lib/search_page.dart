import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

enum _Mode { name, tag, country }

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

class _SearchPageState extends State<SearchPage> {
  final _text = TextEditingController();
  _Mode _mode = _Mode.name;
  Timer? _debounce;
  int _seq = 0;
  bool _loading = false;
  String? _error;
  List<Station>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 550), _run);
  }

  Future<void> _run() async {
    final q = _text.text.trim();
    final seq = ++_seq;
    if (q.length < 2) {
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
      final r = await RadioApi.i.search(
        name: _mode == _Mode.name ? q : '',
        tag: _mode == _Mode.tag ? q.toLowerCase() : '',
        country: _mode == _Mode.country ? q : '',
      );
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
    setState(() => _mode = _Mode.tag);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: SearchBar(
              controller: _text,
              hintText: switch (_mode) {
                _Mode.name => 'Nome della radio',
                _Mode.tag => 'Genere: jazz, news, rock…',
                _Mode.country => 'Paese: Morocco, Italy…',
              },
              leading: const Icon(Icons.search),
              trailing: [
                if (_text.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _text.clear();
                      _run();
                    },
                  ),
              ],
              onChanged: _changed,
              onSubmitted: (_) => _run(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(value: _Mode.name, label: Text('Nome'), icon: Icon(Icons.radio)),
                ButtonSegment(value: _Mode.tag, label: Text('Genere'), icon: Icon(Icons.music_note)),
                ButtonSegment(value: _Mode.country, label: Text('Paese'), icon: Icon(Icons.flag)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) {
                setState(() => _mode = s.first);
                _run();
              },
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
          Expanded(
            child: _error != null
                ? Center(child: Text(_error!))
                : results == null
                    ? _home()
                    : results.isEmpty
                        ? const Center(child: Text('Nessuna radio trovata'))
                        : ListView.builder(
                            itemCount: results.length,
                            itemBuilder: (_, i) => StationTile(results[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _home() {
    final top = StationStore.i.stations.take(30).toList();
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Generi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, tag) in _genres)
                ActionChip(label: Text(label), onPressed: () => _genre(tag)),
            ],
          ),
        ),
        if (top.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text('Le più ascoltate nel mondo',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          for (final s in top) StationTile(s),
        ],
      ],
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Radio Browser (radio-browser.info): elenco gratuito e aperto di radio di tutto il mondo.
/// Ha più server: se uno non risponde si passa al successivo.
class RadioApi {
  RadioApi._();
  static final i = RadioApi._();

  static const _hosts = [
    'de1.api.radio-browser.info',
    'de2.api.radio-browser.info',
    'fi1.api.radio-browser.info',
    'nl1.api.radio-browser.info',
    'at1.api.radio-browser.info',
    'all.api.radio-browser.info',
  ];
  static const _headers = {'User-Agent': 'DevooRadio/1.0'};

  final http.Client _client = http.Client();
  String? _good;

  Future<String> _get(String path, Map<String, String> query,
      {Duration timeout = const Duration(seconds: 20)}) async {
    final others = _hosts.where((h) => h != _good).toList()..shuffle();
    final order = [if (_good != null) _good!, ...others];
    Object? last;
    for (final h in order) {
      try {
        final r = await _client
            .get(Uri.https(h, path, query.isEmpty ? null : query), headers: _headers)
            .timeout(timeout);
        if (r.statusCode == 200) {
          _good = h;
          return utf8.decode(r.bodyBytes, allowMalformed: true);
        }
        last = 'HTTP ${r.statusCode}';
      } catch (e) {
        last = e;
      }
    }
    throw Exception('Server radio non raggiungibili ($last)');
  }

  /// Una pagina di stazioni con posizione sulla mappa, le più ascoltate prima.
  /// Ritorna (stazioni valide, quante ne ha mandate il server).
  Future<(List<Station>, int)> geoPage(int offset, int limit) async {
    final body = await _get(
      '/json/stations/search',
      {
        'has_geo_info': 'true',
        'hidebroken': 'true',
        'order': 'clickcount',
        'reverse': 'true',
        'offset': '$offset',
        'limit': '$limit',
      },
      timeout: const Duration(seconds: 60),
    );
    return compute(parseStations, body);
  }

  /// Ricerca per nome, genere o paese (anche radio senza posizione).
  Future<List<Station>> search({String name = '', String tag = '', String country = ''}) async {
    final body = await _get('/json/stations/search', {
      if (name.isNotEmpty) 'name': name,
      if (tag.isNotEmpty) 'tag': tag,
      if (country.isNotEmpty) 'country': country,
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
      'limit': '100',
    });
    return (await compute(parseStations, body)).$1;
  }

  /// Segnala l'ascolto a Radio Browser (aiuta la classifica). Non blocca mai.
  void click(String id) {
    _get('/json/url/$id', const {}, timeout: const Duration(seconds: 10))
        .then((_) {}, onError: (_) {});
  }
}

/// Eseguito in un isolate separato: l'interfaccia resta fluida.
(List<Station>, int) parseStations(String body) {
  final Object? data;
  try {
    data = jsonDecode(body);
  } catch (_) {
    return (const <Station>[], 0);
  }
  if (data is! List) return (const <Station>[], 0);
  final out = <Station>[];
  for (final j in data) {
    if (j is Map<String, dynamic>) {
      final s = Station.fromApi(j);
      if (s != null) out.add(s);
    }
  }
  return (out, data.length);
}

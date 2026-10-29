import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

/// Tutte le radio della mappa. Salvate sul telefono: si apre subito anche offline,
/// e si aggiornano da sole una volta a settimana.
class StationStore extends ChangeNotifier {
  StationStore._();
  static final i = StationStore._();

  static const _pageSize = 5000;
  static const _maxStations = 50000;
  static const _maxAge = Duration(days: 7);

  List<Station> stations = const [];
  List<Place> places = const [];
  bool loading = false;
  double progress = 0;
  String? error;

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/stations_v1.json');
  }

  Future<void> init() async {
    var fresh = false;
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = await compute(_decode, await f.readAsString());
        if (list.isNotEmpty) {
          _set(list);
          fresh = DateTime.now().difference(await f.lastModified()) < _maxAge;
        }
      }
    } catch (_) {
      // cache rovinata: si riscarica
    }
    if (!fresh) unawaited(refresh());
  }

  void _set(List<Station> list) {
    stations = List.unmodifiable(list);
    places = buildPlaces(stations);
    notifyListeners();
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    error = null;
    progress = 0;
    notifyListeners();

    final firstTime = stations.isEmpty;
    final all = <Station>[];
    final seen = <String>{};
    try {
      var offset = 0;
      while (offset < _maxStations) {
        final size = offset == 0 ? 1000 : _pageSize; // la prima pagina piccola: puntini subito
        final (page, raw) = await RadioApi.i.geoPage(offset, size);
        offset += size;
        for (final s in page) {
          if (seen.add(s.id)) all.add(s);
        }
        progress = offset / _maxStations;
        if (firstTime) _set(all); // i puntini compaiono mentre scarica
        notifyListeners();
        if (raw < size) break; // finite
      }
    } catch (e) {
      if (stations.isEmpty && all.isEmpty) {
        error = 'Nessuna connessione. Controlla internet e riprova.';
      }
    }
    if (all.length >= 50 && all.length >= stations.length ~/ 2) {
      _set(all);
      try {
        final f = await _file();
        final text = await compute(_encode, all);
        await f.writeAsString(text, flush: true);
      } catch (_) {}
    }
    loading = false;
    progress = 1;
    notifyListeners();
  }

  Station? random() {
    if (stations.isEmpty) return null;
    final pool = stations.length > 3000 ? stations.sublist(0, 3000) : stations;
    return pool[DateTime.now().microsecondsSinceEpoch % pool.length];
  }
}

List<Station> _decode(String text) {
  final data = jsonDecode(text);
  if (data is! List) return const [];
  return data.map(Station.fromCompact).whereType<Station>().toList();
}

String _encode(List<Station> list) => jsonEncode(list.map((s) => s.toCompact()).toList());

/// Preferiti e ascoltate di recente.
class Library extends ChangeNotifier {
  Library._();
  static final i = Library._();

  static const _kFav = 'favorites_v1';
  static const _kRecent = 'recents_v1';
  static const _maxRecent = 30;

  SharedPreferences? _prefs;
  List<Station> favorites = [];
  List<Station> recents = [];

  Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      favorites = _read(_kFav);
      recents = _read(_kRecent);
    } catch (_) {}
  }

  List<Station> _read(String key) {
    try {
      final raw = _prefs?.getString(key);
      if (raw == null) return [];
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data.map(Station.fromCompact).whereType<Station>().toList();
    } catch (_) {
      return [];
    }
  }

  void _write(String key, List<Station> list) {
    try {
      _prefs?.setString(key, jsonEncode(list.map((s) => s.toCompact()).toList()));
    } catch (_) {}
  }

  /// 0 = satellite (tipo Google Earth), 1 = scura
  int get mapStyle => _prefs?.getInt('map_style') ?? 0;
  set mapStyle(int v) {
    _prefs?.setInt('map_style', v);
    notifyListeners();
  }

  bool isFavorite(Station s) => favorites.any((f) => f.id == s.id);

  void toggleFavorite(Station s) {
    if (isFavorite(s)) {
      favorites.removeWhere((f) => f.id == s.id);
    } else {
      favorites.insert(0, s);
    }
    _write(_kFav, favorites);
    notifyListeners();
  }

  void addRecent(Station s) {
    recents.removeWhere((r) => r.id == s.id);
    recents.insert(0, s);
    if (recents.length > _maxRecent) recents = recents.sublist(0, _maxRecent);
    _write(_kRecent, recents);
    notifyListeners();
  }

  void clearRecents() {
    recents = [];
    _write(_kRecent, recents);
    notifyListeners();
  }
}

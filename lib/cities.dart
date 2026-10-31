import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'models.dart';

/// Città vere (GeoNames, sopra 15.000 abitanti) per mettere ogni radio nella sua città.
/// Il campo "regione" delle radio è spesso sbagliato: si cerca il nome della città
/// nella regione e nel nome della radio, poi si usa la posizione sulla mappa.
class CityIndex {
  CityIndex._(this.cities, this._alias);
  final List<GeoCity> cities; // dalla più grande
  final Map<String, int> _alias; // nome normalizzato → città

  static String? _raw;
  static final Map<String, CityIndex> _byCountry = {};

  static Future<CityIndex> of(String countryCode) async {
    final cc = countryCode.toUpperCase();
    final hit = _byCountry[cc];
    if (hit != null) return hit;
    _raw ??= await rootBundle.loadString('assets/cities.tsv');
    final idx = await compute(_build, (_raw!, cc));
    return _byCountry[cc] = idx;
  }

  /// La città di una radio, oppure null (radio nazionale o web).
  GeoCity? cityOf(Station s) {
    final byState = _find(s.state);
    if (byState != null) return byState;
    final byName = _find(s.name);
    if (byName != null) return byName;
    if (s.hasGeo) return _nearest(s.lat!, s.lng!);
    return null;
  }

  GeoCity? _find(String text) {
    final words = normCity(text).split(' ').where((w) => w.isNotEmpty).toList();
    int? best;
    for (var n = 3; n >= 1; n--) {
      for (var i = 0; i + n <= words.length; i++) {
        final c = _alias[words.sublist(i, i + n).join(' ')];
        if (c != null && (best == null || c < best)) best = c;
      }
    }
    return best == null ? null : cities[best];
  }

  GeoCity? _nearest(double lat, double lng) {
    GeoCity? best;
    var bestKm = 40.0;
    final k = math.cos(lat * math.pi / 180);
    for (final c in cities) {
      final dy = (c.lat - lat) * 111, dx = (c.lng - lng) * 111 * k;
      final d = math.sqrt(dx * dx + dy * dy);
      // le città grandi "attirano" un po' di più
      final w = d - math.min(10, c.population / 300000);
      if (w < bestKm) {
        bestKm = w;
        best = c;
      }
    }
    return best;
  }
}

class GeoCity {
  const GeoCity(this.name, this.lat, this.lng, this.population);
  final String name;
  final double lat, lng;
  final int population;
}

/// Nomi usati dalle radio ma assenti nell'elenco.
const _extra = {
  'MA': {
    'casa': 'Casablanca',
    'dar el beida': 'Casablanca',
    'angad': 'Oujda',
    'oriental': 'Oujda',
    'tanja': 'Tangier',
    'tanger': 'Tangier',
    'souss': 'Agadir',
    'marrakech': 'Marrakesh',
    'fez': 'Fes',
  },
};

CityIndex _build((String, String) a) {
  final (raw, cc) = a;
  final cities = <GeoCity>[];
  final alias = <String, int>{};
  final primary = <String>{};
  final prefix = '$cc\t';
  final alts = <int, List<String>>{};
  for (final line in raw.split('\n')) {
    if (!line.startsWith(prefix)) continue;
    final f = line.split('\t');
    if (f.length < 5) continue;
    final i = cities.length;
    cities.add(GeoCity(f[1], double.tryParse(f[2]) ?? 0, double.tryParse(f[3]) ?? 0, int.tryParse(f[4]) ?? 0));
    final key = normCity(f[1]);
    // il nome vero vince sempre sui nomi alternativi; a parità, la città più grande (indice più basso)
    if (key.length >= 3 && !primary.contains(key)) {
      alias[key] = i;
      primary.add(key);
    }
    if (f.length > 5 && f[5].isNotEmpty) alts[i] = f[5].split('|');
  }
  alts.forEach((i, list) {
    for (final a in list) {
      final k = normCity(a);
      if (k.length < 4 || primary.contains(k)) continue;
      final old = alias[k];
      if (old == null || i < old) alias[k] = i;
    }
  });
  _extra[cc]?.forEach((k, name) {
    final i = cities.indexWhere((c) => c.name == name);
    if (i >= 0) alias[k] = i;
  });
  return CityIndex._(cities, alias);
}

const _from = 'àáâãäåāăąçćčďđèéêëēėęěğģìíîïīįıķĺļľłñńņňòóôõöøōőŕřśşšșţťțùúûüūůűųýÿžźżḩḑḍṭṣẓāīū';
const _to = 'aaaaaaaaacccddeeeeeeeegiiiiiiiikllllnnnnoooooooorrsssstttuuuuuuuuyyzzzhddtszaiu';

/// minuscole, senza accenti, solo lettere e spazi
String normCity(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    final i = _from.indexOf(ch);
    if (i >= 0) {
      b.write(_to[i]);
    } else if (r == 0xDF) {
      b.write('ss');
    } else if ((r >= 0x61 && r <= 0x7A) || (r >= 0x30 && r <= 0x39) || (r >= 0x0600 && r <= 0x06FF) || r > 0x24F) {
      b.write(ch);
    } else {
      b.write(' ');
    }
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

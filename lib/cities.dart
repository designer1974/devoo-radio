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

  /// La città vicina: conta la distanza ma anche la grandezza (un quartiere non batte la città).
  GeoCity? _nearest(double lat, double lng) {
    GeoCity? best;
    var bestScore = 0.0;
    final k = math.cos(lat * math.pi / 180);
    for (final c in cities) {
      final dy = (c.lat - lat) * 111, dx = (c.lng - lng) * 111 * k;
      final d = math.sqrt(dx * dx + dy * dy);
      if (d > 45) continue;
      final score = c.population / ((d + 4) * (d + 4));
      if (score > bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  /// Tutte le radio di un paese: prima ognuna da sola, poi le radio della stessa
  /// emittente (es. "Radio Medi1 - Jazz", "Radio Medi1 - Hits") prendono la città dell'emittente.
  Map<String, GeoCity?> assignAll(List<Station> all, String countryCode) {
    final out = <String, GeoCity?>{};
    final brands = _brands[countryCode.toUpperCase()] ?? const {};
    for (final s in all) {
      var c = cityOf(s);
      if (c == null) {
        final n = ' ${normCity(s.name)} ';
        for (final e in brands.entries) {
          if (n.contains(' ${e.key} ')) {
            c = _byName(e.value);
            break;
          }
        }
      }
      out[s.id] = c;
    }
    // stessa emittente → stessa città, se le radio già trovate sono d'accordo
    final votes = <String, Map<GeoCity, int>>{};
    for (final s in all) {
      final c = out[s.id];
      if (c == null) continue;
      final b = brandOf(s.name);
      if (b == null) continue;
      final m = votes.putIfAbsent(b, () => {});
      m[c] = (m[c] ?? 0) + 1;
    }
    for (final s in all) {
      if (out[s.id] != null) continue;
      final b = brandOf(s.name);
      final m = b == null ? null : votes[b];
      if (m == null || m.isEmpty) continue;
      final total = m.values.fold<int>(0, (a, v) => a + v);
      final top = m.entries.reduce((a, v) => a.value >= v.value ? a : v);
      if (top.value / total >= 0.7) out[s.id] = top.key;
    }
    return out;
  }

  GeoCity? _byName(String name) {
    for (final c in cities) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// "Radio Medi1 - Jazz" → "radio medi1"; "Hit Radio 100% Urban" → "hit radio".
String? brandOf(String name) {
  final head = name.split(RegExp(r'\s[-–|:]\s|\(|\[|/')).first;
  final words = normCity(head).split(' ').where((w) => w.isNotEmpty && !RegExp(r'^\d').hasMatch(w)).toList();
  if (words.isEmpty) return null;
  final b = words.take(2).join(' ');
  return b.length >= 5 ? b : null;
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
    'souss massa': 'Agadir',
    'casablanca settat': 'Casablanca',
    'fes meknes': 'Fes',
    'marrakech safi': 'Marrakesh',
    'tanger tetouan al hoceima': 'Tangier',
    'beni mellal khenifra': 'Beni Mellal',
    'draa tafilalet': 'Errachidia',
    'guelmim oued noun': 'Guelmim',
    'laayoune sakia el hamra': 'Laayoune',
    'dakhla oued ed dahab': 'Dakhla',
    'el jadida': 'El Jadida',
    'eljadida': 'El Jadida',
    'mazagan': 'El Jadida',
  },
};

/// Emittenti conosciute senza città nei dati: la città della sede.
const _brands = {
  'MA': {
    'medi1': 'Tangier',
    'medi 1': 'Tangier',
    'cap radio': 'Tangier',
    'hit radio': 'Rabat',
    'snrt': 'Rabat',
    'idaa watania': 'Rabat',
    'radio nationale': 'Rabat',
    'chaine inter': 'Rabat',
    'radio mohammed vi': 'Rabat',
    'radio mars': 'Casablanca',
    'aswat': 'Casablanca',
    'med radio': 'Casablanca',
    'medradio': 'Casablanca',
    'mfm': 'Casablanca',
    'atlantic': 'Casablanca',
    'chada': 'Casablanca',
    'luxe radio': 'Casablanca',
    '2m': 'Casablanca',
    'yabiladi': 'Casablanca',
    'medina fm': 'Casablanca',
    'adwaa': 'Casablanca',
    'achkid': 'Casablanca',
    'skyrock': 'Casablanca',
    'radio plus': 'Marrakesh',
  },
};

CityIndex _build((String, String) a) {
  final (raw, cc) = a;
  // il Marocco comprende anche le città del Sahara (Laayoune, Dakhla)
  final prefixes = cc == 'MA' ? ['MA\t', 'EH\t'] : ['$cc\t'];
  final rows = <List<String>>[];
  for (final line in raw.split('\n')) {
    if (!prefixes.any(line.startsWith)) continue;
    final f = line.split('\t');
    if (f.length >= 5) rows.add(f);
  }
  rows.sort((x, y) => (int.tryParse(y[4]) ?? 0).compareTo(int.tryParse(x[4]) ?? 0));
  final cities = <GeoCity>[];
  final alias = <String, int>{};
  final primary = <String>{};
  final alts = <int, List<String>>{};
  for (final f in rows) {
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

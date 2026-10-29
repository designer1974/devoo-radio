import 'dart:math' as math;

/// Bandiera emoji dal codice paese (IT → 🇮🇹). Codice non valido → 🌐
String flagEmoji(String code) {
  final c = code.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(c)) return '🌐';
  return String.fromCharCodes(c.codeUnits.map((u) => 0x1F1E6 + u - 65));
}

String _s(Object? v) => v == null ? '' : v.toString().trim();

int _i(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(_s(v)) ?? 0;
}

double? _d(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse(_s(v));
}

/// Una stazione radio.
class Station {
  final String id;
  final String name;
  final String url;
  final String favicon;
  final String country;
  final String countryCode;
  final String state;
  final String tags;
  final String codec;
  final int bitrate;
  final double? lat;
  final double? lng;
  final String homepage;

  const Station({
    required this.id,
    required this.name,
    required this.url,
    this.favicon = '',
    this.country = '',
    this.countryCode = '',
    this.state = '',
    this.tags = '',
    this.codec = '',
    this.bitrate = 0,
    this.lat,
    this.lng,
    this.homepage = '',
  });

  bool get hasGeo => lat != null && lng != null;
  String get flag => flagEmoji(countryCode);

  String get place {
    final parts = [if (state.isNotEmpty) state, if (country.isNotEmpty) country];
    return parts.isEmpty ? 'Mondo' : parts.join(', ');
  }

  String get quality => [
        if (codec.isNotEmpty && codec.toUpperCase() != 'UNKNOWN') codec,
        if (bitrate > 0) '$bitrate kbps',
      ].join(' · ');

  List<String> get tagList =>
      tags.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).take(4).toList();

  bool get hasLogo => favicon.startsWith('http');

  /// Dal formato di Radio Browser. Ritorna null se i dati sono inutilizzabili.
  static Station? fromApi(Map<String, dynamic> j) {
    final id = _s(j['stationuuid']);
    final resolved = _s(j['url_resolved']);
    final url = resolved.startsWith('http') ? resolved : _s(j['url']);
    final name = _s(j['name']);
    if (id.isEmpty || name.isEmpty || !url.startsWith('http')) return null;
    double? lat = _d(j['geo_lat']);
    double? lng = _d(j['geo_long']);
    if (lat == null ||
        lng == null ||
        lat.isNaN ||
        lng.isNaN ||
        lat.abs() > 85 ||
        lng.abs() > 180 ||
        (lat == 0 && lng == 0)) {
      lat = null;
      lng = null;
    }
    return Station(
      id: id,
      name: name,
      url: url,
      favicon: _s(j['favicon']),
      country: _s(j['country']),
      countryCode: _s(j['countrycode']).toUpperCase(),
      state: _s(j['state']),
      tags: _s(j['tags']),
      codec: _s(j['codec']),
      bitrate: _i(j['bitrate']),
      lat: lat,
      lng: lng,
      homepage: _s(j['homepage']),
    );
  }

  /// Formato compatto per il salvataggio sul telefono.
  List<Object?> toCompact() =>
      [id, name, url, favicon, country, countryCode, state, tags, codec, bitrate, lat, lng, homepage];

  static Station? fromCompact(Object? o) {
    if (o is! List || o.length < 13) return null;
    final id = _s(o[0]), url = _s(o[2]);
    if (id.isEmpty || !url.startsWith('http')) return null;
    return Station(
      id: id,
      name: _s(o[1]),
      url: url,
      favicon: _s(o[3]),
      country: _s(o[4]),
      countryCode: _s(o[5]),
      state: _s(o[6]),
      tags: _s(o[7]),
      codec: _s(o[8]),
      bitrate: _i(o[9]),
      lat: _d(o[10]),
      lng: _d(o[11]),
      homepage: _s(o[12]),
    );
  }

  @override
  bool operator ==(Object other) => other is Station && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Un punto sulla mappa: una città/zona con una o più radio.
class Place {
  final double lat;
  final double lng;
  final String label;
  final String countryCode;
  final List<Station> stations;

  const Place(this.lat, this.lng, this.label, this.countryCode, this.stations);

  String get flag => flagEmoji(countryCode);
}

String _cellKey(double lat, double lng) => '${(lat * 10).round()}_${(lng * 10).round()}';

/// Raggruppa le stazioni vicine (circa 10 km) in un solo punto.
List<Place> buildPlaces(Iterable<Station> stations) {
  final groups = <String, List<Station>>{};
  for (final s in stations) {
    if (!s.hasGeo) continue;
    groups.putIfAbsent(_cellKey(s.lat!, s.lng!), () => []).add(s);
  }
  final places = <Place>[];
  for (final g in groups.values) {
    var lat = 0.0, lng = 0.0;
    final names = <String, int>{};
    for (final s in g) {
      lat += s.lat!;
      lng += s.lng!;
      final n = s.state.isNotEmpty ? s.state : s.country;
      if (n.isNotEmpty) names[n] = (names[n] ?? 0) + 1;
    }
    var label = g.first.country;
    var best = 0;
    names.forEach((k, v) {
      if (v > best) {
        best = v;
        label = k;
      }
    });
    final country = g.first.country;
    if (label != country && country.isNotEmpty) label = '$label, $country';
    places.add(Place(lat / g.length, lng / g.length, label.isEmpty ? 'Mondo' : label,
        g.first.countryCode, List.unmodifiable(g)));
  }
  // i punti più grandi disegnati per ultimi (sopra)
  places.sort((a, b) => a.stations.length.compareTo(b.stations.length));
  return places;
}

double normalizeLng(double lng) => ((lng + 180) % 360 + 360) % 360 - 180;

/// Il punto più vicino al tocco, entro [maxPx] pixel sullo schermo.
Place? nearestPlace(List<Place> places, double lat, double lng, double zoom, {double maxPx = 26}) {
  if (places.isEmpty) return null;
  lng = normalizeLng(lng);
  final k = 256 * math.pow(2, zoom) / 360; // pixel per grado di longitudine
  final cosLat = math.cos(lat * math.pi / 180).abs().clamp(0.05, 1.0);
  Place? best;
  var bestD = maxPx * maxPx;
  for (final p in places) {
    var dLng = (p.lng - lng).abs();
    if (dLng > 180) dLng = 360 - dLng;
    final dx = dLng * k;
    final dy = (p.lat - lat) * k / cosLat;
    final d = dx * dx + dy * dy;
    if (d <= bestD) {
      bestD = d;
      best = p;
    }
  }
  return best;
}

/// Nomi italiani dei paesi più cercati (il server li ha in inglese).
const italianCountryNames = {
  'MA': 'Marocco', 'DZ': 'Algeria', 'TN': 'Tunisia', 'LY': 'Libia', 'EG': 'Egitto',
  'SA': 'Arabia Saudita', 'AE': 'Emirati Arabi Uniti', 'QA': 'Qatar', 'KW': 'Kuwait',
  'BH': 'Bahrein', 'OM': 'Oman', 'YE': 'Yemen', 'JO': 'Giordania', 'LB': 'Libano',
  'SY': 'Siria', 'IQ': 'Iraq', 'PS': 'Palestina', 'IL': 'Israele', 'TR': 'Turchia',
  'IR': 'Iran', 'SD': 'Sudan', 'MR': 'Mauritania', 'SN': 'Senegal', 'ML': 'Mali',
  'NG': 'Nigeria', 'GH': 'Ghana', 'CI': "Costa d'Avorio", 'CM': 'Camerun', 'KE': 'Kenya',
  'ET': 'Etiopia', 'ZA': 'Sudafrica', 'IT': 'Italia', 'FR': 'Francia', 'ES': 'Spagna',
  'PT': 'Portogallo', 'DE': 'Germania', 'AT': 'Austria', 'CH': 'Svizzera', 'BE': 'Belgio',
  'NL': 'Paesi Bassi', 'LU': 'Lussemburgo', 'GB': 'Regno Unito', 'IE': 'Irlanda',
  'DK': 'Danimarca', 'NO': 'Norvegia', 'SE': 'Svezia', 'FI': 'Finlandia', 'IS': 'Islanda',
  'PL': 'Polonia', 'CZ': 'Repubblica Ceca', 'SK': 'Slovacchia', 'HU': 'Ungheria',
  'RO': 'Romania', 'BG': 'Bulgaria', 'GR': 'Grecia', 'AL': 'Albania', 'RS': 'Serbia',
  'HR': 'Croazia', 'SI': 'Slovenia', 'BA': 'Bosnia ed Erzegovina', 'MK': 'Macedonia del Nord',
  'ME': 'Montenegro', 'UA': 'Ucraina', 'RU': 'Russia', 'BY': 'Bielorussia', 'MD': 'Moldavia',
  'LT': 'Lituania', 'LV': 'Lettonia', 'EE': 'Estonia', 'US': 'Stati Uniti', 'CA': 'Canada',
  'MX': 'Messico', 'BR': 'Brasile', 'AR': 'Argentina', 'CL': 'Cile', 'CO': 'Colombia',
  'PE': 'Perù', 'VE': 'Venezuela', 'CU': 'Cuba', 'DO': 'Repubblica Dominicana',
  'CN': 'Cina', 'JP': 'Giappone', 'KR': 'Corea del Sud', 'IN': 'India', 'PK': 'Pakistan',
  'BD': 'Bangladesh', 'ID': 'Indonesia', 'MY': 'Malesia', 'PH': 'Filippine',
  'TH': 'Thailandia', 'VN': 'Vietnam', 'AF': 'Afghanistan', 'AU': 'Australia',
  'NZ': 'Nuova Zelanda', 'VA': 'Città del Vaticano', 'SM': 'San Marino', 'MT': 'Malta',
  'CY': 'Cipro', 'MC': 'Monaco',
};

class Country {
  final String code;
  final String name; // inglese, come sul server
  final int count;
  const Country(this.code, this.name, this.count);

  String get flag => flagEmoji(code);
  String get displayName => italianCountryNames[code] ?? name;

  bool matches(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return true;
    return displayName.toLowerCase().contains(t) ||
        name.toLowerCase().contains(t) ||
        code.toLowerCase() == t;
  }
}

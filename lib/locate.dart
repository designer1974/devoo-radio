import 'dart:convert';

import 'package:http/http.dart' as http;

/// Dove si trova l'utente, dal suo indirizzo IP (niente GPS, niente permessi).
class IpLocation {
  final double lat;
  final double lng;
  final String city;
  final String country;
  final String countryCode;
  const IpLocation(this.lat, this.lng, this.city, this.country, this.countryCode);

  String get label => [if (city.isNotEmpty) city, if (country.isNotEmpty) country].join(', ');
}

double? _num(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// Prova più servizi gratuiti: se uno non risponde passa al successivo.
Future<IpLocation?> locateByIp() async {
  final services = <(Uri, IpLocation? Function(Map))>[
    (
      Uri.https('ipwho.is', '/'),
      (j) => j['success'] == false
          ? null
          : _make(j['latitude'], j['longitude'], j['city'], j['country'], j['country_code']),
    ),
    (
      Uri.https('ipapi.co', '/json/'),
      (j) => _make(j['latitude'], j['longitude'], j['city'], j['country_name'], j['country_code']),
    ),
    (
      Uri.https('get.geojs.io', '/v1/ip/geo.json'),
      (j) => _make(j['latitude'], j['longitude'], j['city'], j['country'], j['country_code']),
    ),
  ];
  for (final (uri, parse) in services) {
    try {
      final r = await http.get(uri, headers: {'User-Agent': 'DevooRadio/1.0'}).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) continue;
      final j = jsonDecode(r.body);
      if (j is! Map) continue;
      final loc = parse(j);
      if (loc != null) return loc;
    } catch (_) {}
  }
  return null;
}

IpLocation? _make(Object? lat, Object? lng, Object? city, Object? country, Object? cc) {
  final la = _num(lat), lo = _num(lng);
  if (la == null || lo == null || (la == 0 && lo == 0)) return null;
  return IpLocation(la, lo, '${city ?? ''}'.trim(), '${country ?? ''}'.trim(), '${cc ?? ''}'.trim().toUpperCase());
}

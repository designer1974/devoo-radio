import 'package:devoo_radio/api.dart';
import 'package:devoo_radio/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bandiere', () {
    expect(flagEmoji('it'), '🇮🇹');
    expect(flagEmoji('MA'), '🇲🇦');
    expect(flagEmoji(''), '🌐');
    expect(flagEmoji('123'), '🌐');
  });

  test('stazione da Radio Browser, dati sporchi non rompono', () {
    final s = Station.fromApi({
      'stationuuid': 'abc',
      'name': ' Radio Test ',
      'url': 'http://x/stream',
      'url_resolved': '',
      'countrycode': 'it',
      'country': 'Italy',
      'state': 'Lazio',
      'bitrate': '128',
      'geo_lat': 41.9,
      'geo_long': '12.5',
    })!;
    expect(s.name, 'Radio Test');
    expect(s.url, 'http://x/stream');
    expect(s.bitrate, 128);
    expect(s.hasGeo, true);
    expect(s.place, 'Lazio, Italy');
    expect(Station.fromApi({'stationuuid': 'x', 'name': 'n', 'url': 'ftp://bad'}), isNull);
    final noGeo = Station.fromApi(
        {'stationuuid': 'y', 'name': 'n', 'url': 'https://ok', 'geo_lat': 0, 'geo_long': 0})!;
    expect(noGeo.hasGeo, false);
  });

  test('salvataggio compatto andata e ritorno', () {
    const s = Station(id: '1', name: 'A', url: 'https://a', lat: 10, lng: 20, bitrate: 64);
    final back = Station.fromCompact(s.toCompact())!;
    expect(back.id, '1');
    expect(back.lat, 10);
    expect(back.bitrate, 64);
    expect(Station.fromCompact('rotto'), isNull);
  });

  test('parsing risposta server', () {
    final (list, raw) = parseStations(
        '[{"stationuuid":"a","name":"A","url":"https://a"},{"bad":1},"x"]');
    expect(raw, 3);
    expect(list.length, 1);
    expect(parseStations('non json').$2, 0);
  });

  test('punti sulla mappa e tocco', () {
    const a = Station(id: '1', name: 'A', url: 'https://a', lat: 41.90, lng: 12.50, country: 'Italy', countryCode: 'IT');
    const b = Station(id: '2', name: 'B', url: 'https://b', lat: 41.91, lng: 12.49, country: 'Italy', countryCode: 'IT');
    const c = Station(id: '3', name: 'C', url: 'https://c', lat: 33.57, lng: -7.59, country: 'Morocco', countryCode: 'MA');
    final places = buildPlaces([a, b, c]);
    expect(places.length, 2);
    final rome = nearestPlace(places, 41.9, 12.5, 5)!;
    expect(rome.stations.length, 2);
    expect(nearestPlace(places, 0, 0, 5), isNull);
    expect(nearestPlace(places, 33.6, -7.6, 5)!.countryCode, 'MA');
    expect(normalizeLng(190), closeTo(-170, 1e-9));
  });
}

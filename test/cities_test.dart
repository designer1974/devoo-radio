import 'package:devoo_radio/cities.dart';
import 'package:devoo_radio/models.dart';
import 'package:flutter_test/flutter_test.dart';

Station st(String name, {String state = '', double? lat, double? lng}) =>
    Station(id: name, name: name, url: 'http://x', countryCode: 'MA', country: 'Morocco', state: state, lat: lat, lng: lng);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('città del Marocco', () async {
    final idx = await CityIndex.of('MA');
    String? c(Station s) => idx.cityOf(s)?.name;
    expect(c(st('Radio X', state: 'casa')), 'Casablanca');
    expect(c(st('Radio Y', state: 'Angad')), 'Oujda');
    expect(c(st('Radio Z', state: 'Rabat-Salé-Kénitra')), 'Rabat');
    expect(c(st('Radio W', state: 'marrakech')), 'Marrakesh');
    expect(c(st('Radio Tanger FM')), 'Tangier');
    expect(c(st('إذاعة طنجة')), 'Tangier');
    expect(c(st('Radio Agadir')), 'Agadir');
    expect(c(st('Hit Radio', state: 'New York')), isNull);
    expect(c(st('Medi 1')), isNull);
    expect(c(st('Geo', lat: 33.6, lng: -7.6)), 'Casablanca');
  });
}

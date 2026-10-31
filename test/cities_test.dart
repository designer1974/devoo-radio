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
    expect(c(st('Geo2', lat: 30.52, lng: -9.63)), 'Agadir');
    expect(c(st('Radio X', state: 'El Jadida')), 'El Jadida');
    expect(c(st('Radio Y', state: 'Laayoune')), 'Laayoune');
    final all = [
      st('Radio Medi1 - Jazz'),
      st('Radio Medi1 - Hits'),
      st('Hit Radio 100% Urban'),
      st('Radio Mars 91.2 FM'),
      st('Zine Bladi'),
    ];
    final m = idx.assignAll(all, 'MA');
    expect(m['Radio Medi1 - Jazz']?.name, 'Tangier');
    expect(m['Radio Medi1 - Hits']?.name, 'Tangier');
    expect(m['Hit Radio 100% Urban']?.name, 'Rabat');
    expect(m['Radio Mars 91.2 FM']?.name, 'Casablanca');
    expect(m['Zine Bladi'], isNull);
    expect(brandOf('Radio Medi1 - Jazz'), 'radio medi1');
  });
}

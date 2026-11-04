import 'package:devoo_radio/license.dart';
import 'package:devoo_radio/ping.dart';
import 'package:flutter_test/flutter_test.dart';

// Chiavi create dal pannello devoo.it/admin (stessa chiave privata di Devoo POS) per il dispositivo «test-id».
const radioKey = 'AEBHC3-5DLJVA-FIMXGQ-GPQF75-QA3PF2-AEIPP4-VTJLKD-O5DBFW-AA5HJN-XYDMXX-CGNP32-GLANPF-F5AUX2-7BTP4O-AFRAW7-QHI5WP-QAHNTR-23YMKW-N6GYMZ-GQK';
const posKey = 'AEAXC3-5DLJVA-FILJ54-ORMFOK-5PQX22-XFDX2B-3W3UM4-34QCNG-PDRQQ5-AR4IZL-S7QJZU-JMROAM-4G4I5J-RURKA2-YU4DUG-NQITBN-VOBZY2-2KSN3W-5OZYQ2-GQO';

void main() {
  test('codice dispositivo della Radio (diverso da Devoo POS)', () async {
    final h = await deviceHash('test-id');
    expect(deviceCodeOf(h), 'OFX2-GWTK');
  });

  test('la chiave Radio del pannello funziona', () async {
    final h = await deviceHash('test-id');
    final lic = await verifyLicense(radioKey, h);
    expect(lic, isNotNull);
    expect(lic!.plan, planRadio);
    expect(lic.expires, DateTime.utc(2027, 11, 5));
  });

  test('una chiave di Devoo POS NON sblocca la Radio', () async {
    final h = await deviceHash('test-id');
    expect(await verifyLicense(posKey, h), isNull);
  });

  test('la chiave Radio non vale su un altro telefono', () async {
    final h = await deviceHash('altro-telefono');
    expect(await verifyLicense(radioKey, h), isNull);
  });

  test('impronta della chiave come il sito', () async {
    expect(await Ping.keyHash(radioKey), '5551e0561ed316dd'); // = lic_hash() del sito
    expect(await Ping.keyHash(radioKey.toLowerCase()), await Ping.keyHash(radioKey));
  });
}

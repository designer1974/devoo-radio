import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Licenze firmate (Ed25519), stesso sistema di Devoo POS: solo chi ha la chiave privata
/// (devoo.it/admin) può crearle, ognuna vale per un solo dispositivo, funzionano offline.
///
/// Chiave = base32( versione | piano | dispositivo(5) | scadenza(2) | firma(64) )
/// - piano 2 = Devoo Radio Pro (le chiavi di Devoo POS hanno piano 1 e qui NON valgono)
/// - scadenza = giorni dal 1/1/2026, 0 = a vita.
const publicKeyHex = 'd3ab2094ce8533b3d06db37f2ff9e70253bafb1a5c52921271eecd129c67eaea';
const planRadio = 2;

final licenseEpoch = DateTime.utc(2026, 1, 1);

class LicenseInfo {
  const LicenseInfo({required this.plan, required this.expires});
  final int plan;

  /// null = a vita.
  final DateTime? expires;

  bool get lifetime => expires == null;
  bool validAt(DateTime now) => expires == null || now.isBefore(expires!);
}

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String base32Encode(List<int> data) {
  final out = StringBuffer();
  var buffer = 0, bits = 0;
  for (final b in data) {
    buffer = (buffer << 8) | (b & 0xff);
    bits += 8;
    while (bits >= 5) {
      out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

Uint8List base32Decode(String s) {
  final out = <int>[];
  var buffer = 0, bits = 0;
  for (final ch in s.toUpperCase().split('')) {
    final v = _alphabet.indexOf(ch);
    if (v < 0) continue; // trattini, spazi, a capo
    buffer = (buffer << 5) | v;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
    buffer &= (1 << bits) - 1;
  }
  return Uint8List.fromList(out);
}

String groupCode(String s, int n) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i += n) {
    if (i > 0) b.write('-');
    b.write(s.substring(i, i + n > s.length ? s.length : i + n));
  }
  return b.toString();
}

/// Impronta del dispositivo: 5 byte dall'ID Android (diversa da quella di Devoo POS).
Future<Uint8List> deviceHash(String androidId) async {
  final h = await Sha256().hash(utf8.encode('devoo-radio|$androidId'));
  return Uint8List.fromList(h.bytes.sublist(0, 5));
}

/// Codice da mandare allo sviluppatore, tipo «7PAX-YFFX».
String deviceCodeOf(List<int> hash) => groupCode(base32Encode(hash), 4);

Uint8List _hex(String h) =>
    Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

/// Controlla una chiave. Ritorna null se non è valida, non è di Devoo Radio o non è di questo dispositivo.
Future<LicenseInfo?> verifyLicense(String key, List<int> device, {String pubHex = publicKeyHex}) async {
  final raw = base32Decode(key);
  if (raw.length < 9 + 64) return null;
  final payload = raw.sublist(0, 9);
  final sig = raw.sublist(9, 9 + 64);
  if (payload[0] != 1 || payload[1] != planRadio) return null;
  for (var i = 0; i < 5; i++) {
    if (payload[2 + i] != device[i]) return null;
  }
  try {
    final ok = await Ed25519().verify(
      payload,
      signature: Signature(sig, publicKey: SimplePublicKey(_hex(pubHex), type: KeyPairType.ed25519)),
    );
    if (!ok) return null;
  } catch (_) {
    return null;
  }
  final days = (payload[7] << 8) | payload[8];
  return LicenseInfo(
    plan: payload[1],
    expires: days == 0 ? null : licenseEpoch.add(Duration(days: days)),
  );
}

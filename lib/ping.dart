import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';
import 'pro.dart';

/// Una volta al giorno, solo con internet, l'app dice a devoo.it che è in uso (come Devoo POS).
/// Manda SOLO: codice dispositivo, modello, build, stato della licenza e scadenza,
/// un'impronta corta della chiave (non la chiave), paese del telefono e lingua.
/// Niente radio ascoltate, registrazioni o altri dati personali.
/// Se dal pannello la licenza è stata bloccata, la toglie.
class Ping {
  Ping._();

  static const url = 'https://devoo.it/api/app-ping.php';
  static const every = Duration(hours: 20);
  static bool _running = false;

  static void start() {
    Timer(const Duration(seconds: 30), run);
    Timer.periodic(const Duration(hours: 6), (_) => run());
  }

  /// Impronta della chiave: uguale a lic_hash() del sito.
  static Future<String> keyHash(String key) async {
    final clean = key.toUpperCase().replaceAll(RegExp('[^A-Z2-7]'), '');
    final h = await Sha256().hash(utf8.encode('devoo-key|$clean'));
    return h.bytes.take(8).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String status(Pro p) {
    if (p.isProPackage || p.licensed) return 'pro';
    if (p.inGrace) return 'grace';
    if (p.inTrial) return 'trial';
    if (p.expired) return 'expired';
    return 'free';
  }

  static Future<void> run() async {
    final p = Pro.i;
    if (_running || !p.ready || p.deviceCode.isEmpty) return;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('ping_at') ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last < every.inMilliseconds) return;
      final sentKey = p.savedKey;
      final e = p.license?.expires;
      String two(int n) => n.toString().padLeft(2, '0');
      final body = {
        'product': 'radio',
        'device': p.deviceCode,
        'platform': 'android',
        'model': p.model,
        'build': appBuild,
        'status': status(p),
        'expires': e == null ? null : '${e.year}-${two(e.month)}-${two(e.day)}',
        'kh': sentKey.isEmpty ? null : await keyHash(sentKey),
        'country': ui.PlatformDispatcher.instance.locale.countryCode?.toUpperCase(),
        'lang': Lang.i.code,
      };
      final r = await http
          .post(Uri.parse(url),
              headers: {'Content-Type': 'application/json', 'User-Agent': 'DevooRadio/$appBuild'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return;
      await prefs.setInt('ping_at', DateTime.now().millisecondsSinceEpoch);
      final j = jsonDecode(r.body);
      if (j is Map && j['revoked'] == true && sentKey.isNotEmpty && p.savedKey == sentKey) {
        await p.deactivate();
      }
    } catch (_) {
      // senza internet: si riprova più tardi
    } finally {
      _running = false;
    }
  }
}

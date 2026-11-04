import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'license.dart';

/// Numero della build (lo scrive GitHub durante la compilazione). 0 = sconosciuto.
const appBuild = int.fromEnvironment('BUILD');

/// Da dove arriva l'app: «site» = APK di devoo.it (chiave di licenza + aggiornamenti da GitHub),
/// «store» = store (pagamenti dello store, aggiornamenti dallo store).
const appDist = String.fromEnvironment('DIST', defaultValue: 'site');

/// Chi ha Pro.
/// - L'app «Devoo Radio Pro» (pacchetto .pro) ha sempre tutto: è la versione dello sviluppatore.
/// - L'APK del sito: chiave di licenza (devoo.it/admin) o prova gratuita di 7 giorni.
/// - Le versioni degli store: abbonamento dello store (da collegare quando ci sono gli account).
class Pro extends ChangeNotifier {
  Pro._();
  static final i = Pro._();
  static const _ch = MethodChannel('rr/recorder');

  /// Limite di registrazione della versione gratuita.
  static const freeRecLimit = Duration(minutes: 10);
  static const trialDays = 7;
  static const graceDays = 3;
  static const warnDays = 7;

  // prezzi mostrati nella pagina Pro
  static const priceMonth = '0,99 €';
  static const priceYear = '3,99 €';

  static const developer = 'Marchoud Rachid';
  static const website = 'devoo.it';
  static const privacyUrl = 'https://devoo.it/privacy';
  static const termsUrl = 'https://devoo.it/termini';

  bool _proPackage = false;
  bool _subscribed = false;
  bool isTv = false;
  bool ready = false;
  String packageName = '';
  String model = '';
  String deviceCode = '';
  List<int> _device = const [];
  LicenseInfo? license;
  String savedKey = '';
  DateTime? trialStart;
  DateTime? clockMax;
  Timer? _timer;

  /// È l'app Pro dello sviluppatore (si aggiorna da GitHub).
  bool get isProPackage => _proPackage;

  /// Momento usato per i controlli: mai prima dell'ultimo visto (chi riporta indietro la data non allunga niente).
  DateTime get _now {
    final n = DateTime.now();
    final m = clockMax;
    return m != null && m.isAfter(n) ? m : n;
  }

  bool get licensed => license != null && license!.validAt(_now);

  bool get inGrace {
    final e = license?.expires;
    if (e == null || licensed) return false;
    return _now.isBefore(e.add(const Duration(days: graceDays)));
  }

  bool get expired => license != null && !license!.validAt(_now);

  DateTime? get trialEnd => trialStart?.add(const Duration(days: trialDays));
  bool get trialUsed => trialStart != null;
  bool get inTrial =>
      !licensed && trialEnd != null && _now.isBefore(trialEnd!) && !trialStart!.isAfter(_now.add(const Duration(days: 1)));

  int? get daysLeft {
    final e = license?.expires ?? (inTrial ? trialEnd : null);
    if (e == null) return null;
    final d = e.difference(_now);
    return d.isNegative ? -((-d.inMinutes + 1439) ~/ 1440) : d.inHours ~/ 24;
  }

  bool get isPro => _proPackage || _subscribed || licensed || inGrace || inTrial;

  String get appName => _proPackage ? 'Devoo Radio Pro' : 'Devoo Radio';

  /// Testo dello stato per la pagina Pro.
  String get statusText {
    String d(DateTime x) {
      final l = x.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${two(l.day)}/${two(l.month)}/${l.year}';
    }

    if (_proPackage) return 'Versione sviluppatore: Pro sempre attivo';
    if (licensed) {
      final e = license!.expires;
      return e == null ? 'Pro attivo · a vita' : 'Pro attivo fino al ${d(e)}';
    }
    if (inGrace) return 'Licenza scaduta il ${d(license!.expires!)}: rinnova subito';
    if (inTrial) return 'Prova Pro attiva fino al ${d(trialEnd!)}';
    if (_subscribed) return 'Abbonamento Pro attivo';
    if (expired) return 'Licenza scaduta';
    if (trialUsed) return 'Prova gratuita terminata';
    return 'Versione gratuita';
  }

  Future<void> init() async {
    String id = '';
    try {
      final m = await _ch.invokeMethod<Map>('appInfo');
      packageName = '${m?['package'] ?? ''}';
      _proPackage = packageName.endsWith('.pro');
      isTv = m?['tv'] == true;
      id = '${m?['id'] ?? ''}';
      model = '${m?['model'] ?? ''}';
    } catch (_) {}
    _device = await deviceHash(id.isEmpty ? 'sconosciuto' : id);
    deviceCode = deviceCodeOf(_device);
    SharedPreferences? p;
    try {
      p = await SharedPreferences.getInstance();
      savedKey = p.getString('license_key') ?? '';
      final t = p.getInt('trial_start');
      if (t != null) trialStart = DateTime.fromMillisecondsSinceEpoch(t);
      final c = p.getInt('clock_max');
      if (c != null) clockMax = DateTime.fromMillisecondsSinceEpoch(c);
    } catch (_) {}
    if (savedKey.isNotEmpty) license = await verifyLicense(savedKey, _device);
    await _checkClock(p);
    ready = true;
    _timer ??= Timer.periodic(const Duration(minutes: 30), (_) async {
      await _checkClock(null);
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> _checkClock(SharedPreferences? p) async {
    final now = DateTime.now();
    final max = clockMax;
    if (max != null && !now.isAfter(max)) return;
    // al massimo un giorno avanti per volta: una data sbagliata nel futuro non toglie giorni
    final step = max == null || now.difference(max) <= const Duration(days: 1) ? now : max.add(const Duration(days: 1));
    clockMax = step;
    try {
      await (p ?? await SharedPreferences.getInstance()).setInt('clock_max', step.millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Avvia la prova gratuita di 7 giorni (una sola volta).
  Future<bool> startTrial() async {
    if (trialUsed || isPro) return false;
    trialStart = DateTime.now();
    try {
      await (await SharedPreferences.getInstance()).setInt('trial_start', trialStart!.millisecondsSinceEpoch);
    } catch (_) {}
    notifyListeners();
    return true;
  }

  /// Attiva una chiave. Ritorna null se va bene, altrimenti il motivo.
  Future<String?> activate(String key) async {
    final k = key.trim();
    if (k.isEmpty) return 'Scrivi la chiave di licenza';
    final lic = await verifyLicense(k, _device);
    if (lic == null) return 'Chiave non valida per questo telefono (serve una chiave di Devoo Radio)';
    await _checkClock(null);
    if (!lic.validAt(_now)) return 'Questa licenza è scaduta';
    final cur = license;
    if (cur != null && licensed && (cur.lifetime || (!lic.lifetime && !lic.expires!.isAfter(cur.expires!)))) {
      return 'Hai già una licenza che dura di più';
    }
    license = lic;
    savedKey = k;
    try {
      await (await SharedPreferences.getInstance()).setString('license_key', k);
    } catch (_) {}
    notifyListeners();
    return null;
  }

  Future<void> deactivate() async {
    license = null;
    savedKey = '';
    try {
      await (await SharedPreferences.getInstance()).remove('license_key');
    } catch (_) {}
    notifyListeners();
  }

  /// Da chiamare quando i pagamenti dello store confermano l'abbonamento.
  void setSubscribed(bool v) {
    if (v == _subscribed) return;
    _subscribed = v;
    notifyListeners();
  }

  Future<bool> openUrl(String url) async {
    try {
      return await _ch.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    } catch (_) {
      return false;
    }
  }
}

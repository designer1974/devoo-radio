import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Chi ha Pro.
/// - L'app «Devoo Radio Pro» (pacchetto .pro) ha sempre tutto: è la versione dello sviluppatore.
/// - L'app degli store «Devoo Radio» è gratis con limiti; Pro si sbloccherà con l'abbonamento
///   (pagamenti Huawei / Samsung da collegare quando ci sono gli account).
class Pro extends ChangeNotifier {
  Pro._();
  static final i = Pro._();
  static const _ch = MethodChannel('rr/recorder');

  /// Limite di registrazione della versione gratuita.
  static const freeRecLimit = Duration(minutes: 10);

  static const developer = 'Marchoud Rachid';
  static const website = 'devoo.it';
  static const privacyUrl = 'https://devoo.it/privacy';
  static const termsUrl = 'https://devoo.it/termini';

  bool _proPackage = false;
  bool _subscribed = false;
  bool isTv = false;
  String packageName = '';

  /// È l'app Pro dello sviluppatore (si aggiorna da GitHub).
  bool get isProPackage => _proPackage;

  bool get isPro => _proPackage || _subscribed;

  String get appName => _proPackage ? 'Devoo Radio Pro' : 'Devoo Radio';

  Future<void> init() async {
    try {
      final m = await _ch.invokeMethod<Map>('appInfo');
      packageName = '${m?['package'] ?? ''}';
      _proPackage = packageName.endsWith('.pro');
      isTv = m?['tv'] == true;
    } catch (_) {}
    notifyListeners();
  }

  /// Da chiamare quando i pagamenti dello store confermano l'abbonamento.
  void setSubscribed(bool v) {
    if (v == _subscribed) return;
    _subscribed = v;
    notifyListeners();
  }
}

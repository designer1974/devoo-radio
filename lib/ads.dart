import 'package:flutter/material.dart' hide Text;
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'paywall.dart';
import 'pro.dart';
import 'widgets.dart';
import 'i18n.dart';

/// ID di PROVA di Google: da sostituire con quelli del tuo account AdMob prima di pubblicare.
const _bannerId = 'ca-app-pub-3940256099942544/6300978111';

bool _adsStarted = false;

Future<void> initAds() async {
  if (Pro.i.isPro || _adsStarted) return;
  _adsStarted = true;
  try {
    await MobileAds.instance.initialize();
  } catch (_) {}
}

/// Banner in basso solo per la versione gratuita. Se la pubblicità non si carica
/// (per esempio su telefoni Huawei senza servizi Google) mostra «Passa a Pro».
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});
  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    Pro.i.addListener(_onPro);
    _load();
  }

  void _onPro() {
    if (Pro.i.isPro) {
      _ad?.dispose();
      _ad = null;
    }
    if (mounted) setState(() {});
  }

  void _load() {
    if (Pro.i.isPro) return;
    if (Pro.i.isTv) {
      _failed = true;
      return;
    }
    try {
      _ad = BannerAd(
        adUnitId: _bannerId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            _ad = null;
            if (mounted) setState(() => _failed = true);
          },
        ),
      )..load();
    } catch (_) {
      _failed = true;
    }
  }

  @override
  void dispose() {
    Pro.i.removeListener(_onPro);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Pro.i.isPro) return const SizedBox.shrink();
    final ad = _ad;
    if (_loaded && ad != null) {
      return SizedBox(
        height: ad.size.height.toDouble(),
        width: double.infinity,
        child: Center(child: SizedBox(width: ad.size.width.toDouble(), child: AdWidget(ad: ad))),
      );
    }
    if (!_failed) return const SizedBox(height: 50);
    // ripiego: promemoria Pro al posto della pubblicità
    return Material(
      color: accent.withValues(alpha: 0.12),
      child: InkWell(
        onTap: () => openPaywall(context),
        child: const SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.workspace_premium, color: accent, size: 20),
              SizedBox(width: 8),
              Text('Senza pubblicità e senza limiti con Pro', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
